

#defaults
properties {
    $xdb_sqlserver=""
    $xdb_database=""
    $xdb_uid=""
    $xdb_pwd=""
    $xdb_home_path=""
    $matrix_iis_install=$false
    $matrix_db_install=$false
    $matrix_web_root="C:\Users\PLA\Work\Xenfunds\src\xpm\Release\Package\"
    $matrix_backup_root=""
    $matrix_website_name="XPM"
    $matrix_apppool_name=""
}

#Run the command. Check for success.
function RunCommand($cmd) {

        $Output = Invoke-Expression -command $cmd

        if ($LASTEXITCODE)
        { 
            throw $cmd + " failed: "+"`n"+ $Output
        }
}

function ExtractWebPackage() {

    if(-not (Test-Path ".\Payload\Web.zip")){     
        throw "cant find the package."  
    }
    
    Expand-Archive -Path .\Payload\Web.zip -DestinationPath .\Payload\
}

#default task, causes Finalise (final step) to be run and all dependencies in the chain to be built
task Default -depends Finalise 

task SQLMigrate -precondition { return $matrix_db_install } -description "Database migration" {

    Set-Location $PSScriptRoot
    $SchemaDir=[System.IO.Path]::Combine($PSScriptRoot,"Payload\Sql\Migrations")
    $SchemaDir=[System.IO.Path]::GetFullPath($SchemaDir)

    if(Test-Path $SchemaDir\*.sql) {
        #Run the database schema/data migrations
        .\Tools\migrate-db\migrate-db.ps1 -Server $xdb_sqlserver -Database $xdb_database -SchemaDir $SchemaDir -Module "XPM"
    }  
}

task SQLCode -depends SQLMigrate -precondition { return $matrix_db_install } -description "Database Sql Code install" {
    Set-Location $PSScriptRoot\Payload\Sql\Code 
    
    #Run the sql upgrade scripts
    if($xdb_uid)
    {
        RunCommand "sqlcmd -d $xdb_database -U $xdb_uid -P $xdb_pwd -i views-code-help.sql -S $xdb_sqlserver -b"
    }
    else {
        RunCommand "sqlcmd -d $xdb_database -E -i views-code-help.sql -S $xdb_sqlserver -b"
    }

    Set-Location $PSScriptRoot
}

task ScriptModule -depends SQLCode -precondition { return $matrix_db_install } -description "Script module install" {
    <# todo
    Set-Location $PSScriptRoot
    if(!$xdb_home_path){Throw "Environment error. xdb_home_path is not defined."}
    
    $modulePath=[System.IO.Path]::Combine($xdb_home_path,"App\Scripts\Modules\mx-xpm")
    $modulePath=[System.IO.Path]::GetFullPath($modulePath)

    $exists=Test-Path -Path $modulePath
    If(!$exists) {
        mkdir $modulePath
    }

    #Publish the Powershell module
    robocopy Payload\App\Scripts\Modules\mx-im $modulePath /MIR
    #Need to check the exit code - see here https://superuser.com/questions/280425/getting-robocopy-to-return-a-proper-exit-code
    if($lastexitcode -ge 8) {throw "Copy failed."}

    #>
}

task InitializeWebDeploy -precondition { return $matrix_iis_install } -description "Initialize IIS settings and Load IIS PS modules." {

    Set-Location $PSScriptRoot
    
    Write-Host "matrix_web_root : $matrix_web_root"
    Write-Host "matrix_website_name : $matrix_website_name"

    if (-not ($matrix_web_root -and $matrix_website_name))
    {
        throw "IIS/Website settings not available"
    }

    $script:matrix_apppool_name = If ($matrix_apppool_name) {$matrix_apppool_name} Else {$matrix_website_name}
    $script:matrix_website_root = [System.IO.Path]::Combine($matrix_web_root, $matrix_website_name)
    $script:matrix_backup_root = If ($matrix_backup_root) {$matrix_backup_root} Else {[System.IO.Path]::Combine($matrix_web_root, "Backups")}
    
    Write-Host "matrix_apppool_name : $script:matrix_apppool_name"
    Write-Host "matrix_website_root : $script:matrix_website_root"
    Write-Host "matrix_backup_root : $script:matrix_backup_root"
    
    if (-not ($script:matrix_website_root -and $script:matrix_backup_root))
    {
        throw "Missing IIS/Website settings"
    }

    Import-Module WebAdministration
    Import-Module IISAdministration
}

task StopIISSite -depends InitializeWebDeploy -precondition { return $matrix_iis_install } -description "Stop IIS site." {

    Set-Location $PSScriptRoot

    # stop iis site and app pool, try 4 times with 2 seconds interval if failed
    $currentRetry = 0;
    $success = $false;
    do{
        try{
            Stop-IISSite -Name $matrix_website_name -Confirm:$false
            Stop-WebAppPool -Name $script:matrix_apppool_name
        }
        catch {}

        # assumed app pool name is similar to site name
        $website_status = Get-WebsiteState -name $matrix_website_name
        $apppool_status = Get-WebAppPoolState -name $script:matrix_apppool_name
        if ($website_status.Value -eq "Stopped" -and $apppool_status.Value -eq "Stopped"){
            $success = $true;
            break;
        }

        Start-Sleep -s 2
        $currentRetry = $currentRetry + 1;

    }
    while (!$success -and $currentRetry -le 4)

    if(!$success){
        throw "Can't stop the IIS site and app pool. Please stop them manually."
    }
}

task BackupIIS -depends StopIISSite -precondition { return $matrix_iis_install } -description "Backup existing IIS folder." {

    Set-Location $PSScriptRoot

    # copy a backup if there is a deployed package
    if(Test-Path $script:matrix_website_root){       

        $backupDir = (Get-Date).tostring("yyyy-MM-dd-hh-mm-ss-fff") 
        $backupDirPath = [System.IO.Path]::Combine($script:matrix_backup_root, $matrix_website_name, $backupDir)

        # append a random number if the backup directory already exist
        if((Test-Path $backupDirPath)){       
            $backupDirPath = $backupDirPath + "_" + (Get-Random -Minimum 1000 -Maximum 9999);
        }

        # create backup directory
        if(-not (Test-Path $backupDirPath)){       
            New-Item -ItemType Directory $backupDirPath
        }

        #Copy-Item "$script:matrix_website_root\*" $backupDirPath -Recurse
        robocopy "$script:matrix_website_root" $backupDirPath /MIR /XD node_modules /R:5 /W:15 /NFL /NDL
        # Check exit code
        If ($LASTEXITCODE -gt 4)
        {
            throw "Robocopy EXITCODE: $LASTEXITCODE"               
        }
    }
}

task PublishToIIS -depends BackupIIS -precondition { return $matrix_iis_install } -description "Copy package to IIS root." {

    Set-Location $PSScriptRoot
    
    # extract zip package if web package not exist
    if(-not (Test-Path ".\Payload\Web")){
        ExtractWebPackage
    }else{
        $directoryInfo = Get-ChildItem ".\Payload\Web" | Measure-Object
        if($directoryInfo.count -eq 0){
            ExtractWebPackage
        }
    }

    $directoryInfo = Get-ChildItem ".\Payload\Web" | Measure-Object
    if($directoryInfo.count -eq 0){
        throw "cant find the package."  
    }

    # remove all but web.config
    Get-ChildItem -Path  $script:matrix_website_root -Recurse -exclude web.config | Remove-Item -Recurse -force 

    robocopy ".\Payload\Web" "$script:matrix_website_root" /MIR /R:5 /W:15 /xf web.config /NFL /NDL
    If ($LASTEXITCODE -gt 4)
    {
        throw "Robocopy EXITCODE: $LASTEXITCODE"               
    }

    # copy web.config if its not available in the destination
    if(-not (Test-Path "$script:matrix_website_root\web.config")){
        if(Test-Path ".\Payload\Web\web.config"){
            robocopy ".\Payload\Web" "$script:matrix_website_root" web.config /MIR /R:5 /W:15 /NFL /NDL
        }else{
            Write-Host -ForegroundColor Yellow "Warning:Can't find a web.config file in the package."
        }
    }
}

task RestartIIS -precondition { return $matrix_iis_install } -description "Start IIS site and app pool." {

    $status = Get-WebsiteState -name $matrix_website_name
    if ($status.Value -eq "Stopped"){
        Start-IISSite -Name $matrix_website_name
    }

    $status = Get-WebAppPoolState -name $script:matrix_apppool_name
    if ($status.Value -eq "Stopped"){
        Start-WebAppPool -Name $script:matrix_apppool_name
    }
}

task Finalise -depends ScriptModule, PublishToIIS, RestartIIS -description "Finalise" {

}
