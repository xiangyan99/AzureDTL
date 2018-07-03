#Requires -Version 3.0

Push-Location $PSScriptRoot

try {

    iex .\installVSCode.ps1

    . .\startChocolatey.ps1 -PackageList git

    . .\startChocolatey.ps1 -PackageList nodejs

    iex .\installAnsibleExtension.ps1

} finally {

    Pop-Location
}