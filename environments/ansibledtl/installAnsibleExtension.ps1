$url = 'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/vscoss/vsextensions/vscode-ansible/0.5.2/vspackage'

$ansibleExtensionVsix = "${env:Temp}\vscoss.vscode-ansible.vsix"

try
{
    (New-Object System.Net.WebClient).DownloadFile($url, $ansibleExtensionVsix)
}
catch
{
    Write-Error "Failed to download Ansible Extension"
}

try
{
    Start-Process -FilePath "code" -ArgumentList "--install-extension $ansibleExtensionVsix"
}
catch
{
    Write-Error 'Failed to install Ansible Extension'
}