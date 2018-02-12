<#
.SYNOPSIS
Run schema migration scripts on a SQL Server databse
.DESCRIPTION
The database version is kept track of in an extended property ('mx-version') on
the SQL Server database.  The version number comes from the prefix of the
filename of each .sql migration script (see -SchemaDir parameter help for more
information).
See https://gist.github.com/mkropat/1ba7ffd1d14f55f63fb3
.PARAMETER Server
The SQL Server instance to connect to.  For example: (local)\SQLEXPRESS
.PARAMETER Database
The name of the database to run the migration on.
.PARAMETER SchemaDir
A directory containing one or more .sql files that have a numeric prefix in the
filename.  The numeric prefix represents the database version that that
particular migration script upgrades the database to.  Versions are compared by
_string ordering_ to determine which one is greater.  To minimize version
control merge conflicts, it is recommended to use the current date in YYYYMMDD
format, followed by a -NN (-01, -02, etc.) sequentially incrementing counter.
An example schema directory might look like:
  20150221-01-create-table.sql
  20150221-02-populate-table.sql
  20150222-disallow-nulls.sql
.EXAMPLE
.\migrate-db.ps1 -Database 'your-db' -SchemaDir .\Db\Schema
.NOTES
Downgrade/rollback scripts aren't supported.  It wouldn't be hard to add
support for them.
If you get errors like: '"Could not load file or assembly 'Microsoft.SqlServer.BatchParser'
then try running the x86 version of PowerShell.
#>

param(
    [String]
    $Server = '(local)\SQLEXPRESS',

    [parameter(Mandatory=$true)]
    [String]
    $Database,

    [parameter(Mandatory=$true)]
    [String]
    $SchemaDir,

    [parameter(Mandatory=$true)]
    [String]
    $Module
)

#Add-Type -AssemblyName 'Microsoft.SqlServer.Smo, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'
#Don't want to assume a particular version - just load the latest
[void][reflection.assembly]::LoadWithPartialName(“Microsoft.SqlServer.Smo”);
[void][reflection.assembly]::LoadWithPartialName(“Microsoft.SqlServer.ConnectionInfo”);

function main {
    $db = Open-Database $Server $Database

    $script:versionPropertyName = "$Module-version"

    $original = Get-SchemaVersion $db

    Write-Host "Database '$Database', Module '$Module' is at version: $original"


    $migrations = Get-SchemaMigrations $SchemaDir |
        where { $_.Version -gt $original } |
        sort {$_.Version}


    try {
        Invoke-Migrations $db $migrations
    }
    finally {
        $current = Get-SchemaVersion $db

        if ($current -gt $original) {
            Write-Host "It has been migrated to: $current"
        }
        else {
            Write-Host "No migration performed — $original is the current version."
        }
    }
}

function Open-Database($Server, $Database) {
    $conn=New-Object Microsoft.SqlServer.Management.Common.ServerConnection
    $conn.ServerInstance=$Server
    if($Env:xdb_uid) {
        $conn.LoginSecure=$false
        $conn.Login=$Env:xdb_uid
        $conn.Password=$Env:xdb_pwd
    }
    
    $s = New-Object Microsoft.SqlServer.Management.Smo.Server $conn
    $db = $s.Databases[$Database]
    if ($db -eq $null) {
        throw "Unable to open database '$Database'"
    }
    $db
}

function Get-SchemaMigrations($Dir) {
    Get-ChildItem -Path $Dir -File -Filter '*.sql' |
        where { $_ -match '^([-_0-9]+)' } |
        foreach {
            $prefix = ($_.Name | Select-String -Pattern '^([-_0-9]+)').Matches[0].Groups[1].Value

            @{
                Path = $_.FullName
                Version = ($prefix -split '[-_]' | where { $_ }) -join '-'
            }
        } 
}

function Invoke-Migrations($Database, $Migrations) {
    try {
        foreach ($m in $Migrations) {
            Invoke-Migration $Database $m
        }
    }
    catch {
        throw $_.Exception
    }
}

function Invoke-Migration($Database, $Migration) {
    $conn = Get-DbConnection $Database
    $script = Get-Content $Migration.Path -Raw

    $conn.BeginTransaction()

        $Database.ExecuteNonQuery($script)
        Set-SchemaVersion $Database $Migration.Version

    $conn.CommitTransaction()
}

function Get-DbConnection {
    param(
        [Microsoft.SqlServer.Management.Smo.Database]
        $Database
    )

    [Microsoft.SqlServer.Management.Common.ServerConnection]$Database.Parent.ConnectionContext
}



function Get-SchemaVersion {
    param(
        [Microsoft.SqlServer.Management.Smo.Database]
        $Database
    )

    if ($Database.ExtendedProperties.Contains($script:versionPropertyName)) {
        [String]$Database.ExtendedProperties[$script:versionPropertyName].Value
    }
    else {
        '0'
    }
}

function Set-SchemaVersion {
    param(
        [Microsoft.SqlServer.Management.Smo.Database]
        $Database,
        $Version
    )

    if ($Database.ExtendedProperties.Contains($script:versionPropertyName)) {
        $property = $Database.ExtendedProperties[$script:versionPropertyName]
        $property.Value = $Version
        $property.Alter()
    }
    else {
        $property = New-Object Microsoft.SqlServer.Management.Smo.ExtendedProperty -ArgumentList $Database,$script:versionPropertyName,$Version
        $property.Create()
    }
}

main