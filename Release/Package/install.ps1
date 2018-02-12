
$ErrorActionPreference="Stop"
try {
Set-Location $PSScriptRoot
.\load-psake.ps1

Invoke-psake .\steps.ps1 -properties @{
    "xdb_sqlserver"=$Env:xdb_sqlserver;
    "xdb_database"=$Env:xdb_database;
    "xdb_uid"=$Env:xdb_uid;
    "xdb_pwd"=$Env:xdb_pwd;
    "xdb_home_path"=$Env:xdb_home_path;

    "matrix_iis_install"= $true;
    "matrix_db_install"= $Env:matrix_db_install;
    #"matrix_web_root"= $Env:matrix_web_root;
    "matrix_backup_root"= $Env:matrix_backup_root;
    #"matrix_website_name"= $Env:matrix_website_name;
    "matrix_apppool_name"= $Env:matrix_apppool_name;
}

    if(!$psake.build_success){Throw}
}
catch 
{
    Write-Error $_
}

