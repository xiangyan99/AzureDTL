$ansibleSetup = $PSScriptRoot + "\vscoss.vscode-ansible.vsix"

try
{
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Start-Process -FilePath "code" -ArgumentList "--install-extension $ansibleSetup" -Wait
}
catch
{
    Write-Error 'Failed to install Ansible Extension'
}