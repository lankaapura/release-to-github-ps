
#load psake. Avoid loading twice - causes problems.
$loaded=get-module psake
if($loaded -eq $null) {Import-Module $PSScriptRoot\tools\psake-4.6.0\psake.psm1}
