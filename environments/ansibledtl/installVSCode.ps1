$url = 'https://go.microsoft.com/fwlink/?Linkid=852157'

$infPath = $PSScriptRoot + "\vscode.inf"
$vscodeSetup = "${env:Temp}\VSCodeSetup.exe"

try
{
    (New-Object System.Net.WebClient).DownloadFile($url, $vscodeSetup)
}
catch
{
    Write-Error "Failed to download VSCode Setup"
}

try
{
    Start-Process -FilePath $vscodeSetup -ArgumentList "/VERYSILENT /MERGETASKS=!runcode /LOADINF=$infPath"    
}
catch
{
    Write-Error 'Failed to install VSCode'
}