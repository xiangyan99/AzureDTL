$ansibleSetup = $PSScriptRoot + "\vscoss.vscode-ansible.vsix"

try
{
    Start-Process -FilePath "code" -ArgumentList "--install-extension $ansibleSetup"
}
catch
{
    Write-Error 'Failed to install Ansible Extension'
}