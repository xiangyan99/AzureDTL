try
{
    Start-Process -FilePath "code" -ArgumentList "--install-extension vscoss.vscode-ansible.vsix"
}
catch
{
    Write-Error 'Failed to install Ansible Extension'
}