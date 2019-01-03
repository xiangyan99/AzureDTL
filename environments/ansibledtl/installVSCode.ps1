$infPath = $PSScriptRoot + "\vscode.inf"
$vscodeSetup = $PSScriptRoot + "\VSCodeSetup.exe"

try
{
    Start-Process -FilePath $vscodeSetup -ArgumentList "/VERYSILENT /MERGETASKS=!runcode /LOADINF=$infPath" -Wait
}
catch
{
    Write-Error 'Failed to install VSCode'
}