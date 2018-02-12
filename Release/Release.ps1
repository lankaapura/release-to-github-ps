$ErrorActionPreference="Stop"
try {
Set-Location $PSScriptRoot
. ..\Tools\load-psake.ps1

Invoke-psake .\steps.ps1 -properties @{
    "matrix_release_version"= $Env:BUILDKITE_BUILD_NUMBER;
}

    if(!$psake.build_success){Throw}
}
catch 
{
    Write-Error $_
}

