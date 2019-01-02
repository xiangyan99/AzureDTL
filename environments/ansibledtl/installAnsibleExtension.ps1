$url = 'https://github.com/xiangyan99/AzureDTL/blob/Win10/environments/ansibledtl/vscoss.vscode-ansible.vsix'

$ansibleSetup = "${env:Temp}\vscoss.vscode-ansible.vsix"

try
{
    (New-Object System.Net.WebClient).DownloadFile($url, $ansibleSetup)
}
catch
{
    Write-Error "Failed to download VSCode Setup"
}

try
{
    Start-Process -FilePath "code" -ArgumentList "--install-extension $ansibleSetup"
}
catch
{
    Write-Error 'Failed to install Ansible Extension'
}