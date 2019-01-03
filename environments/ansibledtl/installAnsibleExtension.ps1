Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

try
{
    $zipfile = gci -Filter vscoss.vscode-ansible.zip -Recurse | sort -Descending -Property LastWriteTime | select -First 1 -ExpandProperty FullName
    
    Unzip $zipfile "C:\Program Files (x86)\Microsoft VS Code\resources\app\extensions"
}
catch
{
    Write-Error "Failed to install Ansible extension"
}