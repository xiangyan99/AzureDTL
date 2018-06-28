#Requires -Version 3.0

Push-Location $PSScriptRoot

try {

    iex .\installVSCode.ps1

    iex .\startChocolatey.ps1 -PackageList git

    iex .\startChocolatey.ps1 -PackageList nodejs

    code --install-extension .\vscoss.vscode-ansible-0.2.6.vsix

} finally {

    Pop-Location
}