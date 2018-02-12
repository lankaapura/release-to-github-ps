#defaults
properties {
    $release_version = ""
    $project_path="..\Source\Web\XPM\XPM.csproj"
}

#default task, causes Finalise (final step) to be run and all dependencies in the chain to be built
task Default -depends Finalise 

task Initialize -description "Initialize IIS settings and Load IIS PS modules." {

  Set-Location $PSScriptRoot
  
  $script:module = Get-Content -Path ..\module.json -Raw | ConvertFrom-Json 
 
  If ($release_version) {
    $script:release_version = $release_version
  } Else {
    $script:release_version = $script:module.version
  }

  if (-not ($script:release_version))
  {
    throw "Release number not available"
  }
  
  Write-Host "release_version : $script:release_version"
}

task GetDependencies -depends Initialize -description "Get dependencies" {
  Set-Location $PSScriptRoot

#git fetch –tags
#git tag –sort=v:refname


  Set-Location $PSScriptRoot

}

task CreatePackage -depends GetDependencies -description "Create zip package" {
  Set-Location $PSScriptRoot
  
  $exists=Test-Path -Path $PSScriptRoot\Package_$script:release_version.zip 
  if($exists) {Remove-Item $PSScriptRoot\Package_$script:release_version.zip  -Force}

  #zip web package
  Compress-Archive -Path $PSScriptRoot\Package\ -CompressionLevel Fastest -DestinationPath $PSScriptRoot\Package_$script:release_version.zip

  Set-Location $PSScriptRoot

}

task CreateTag -depends CreatePackage -description "Create tag" {
  Set-Location $PSScriptRoot

  Exec {git fetch --tags}
  Exec {git tag v$script:release_version}  
  Exec {git push origin --tags} 

  Set-Location $PSScriptRoot

}

task CreateGithubRelease -depends CreateTag -description "Create release in github" {
  Set-Location $PSScriptRoot

  Exec {
    ..\Tools\hub\bin\hub.exe release create v$script:release_version -m "$script:release_version" -a $PSScriptRoot\Package_$script:release_version.zip
  }

  Set-Location $PSScriptRoot
}

task Finalise -depends CreateGithubRelease -description "Finalise" {
    
    #nothing to do

}


