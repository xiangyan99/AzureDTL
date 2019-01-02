$url = 'https://aka.ms/win32-x64-user-stable'

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

    Restart-Computer
}
catch
{
    Write-Error 'Failed to install VSCode'
}