# Set environment variable
[CmdletBinding()]
param(
    [string] $name,
    [string] $value
)

###################################################################################################
#
# PowerShell configurations
#

# NOTE: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

# Suppress progress bar output.
$ProgressPreference = 'SilentlyContinue'

# Ensure we force use of TLS 1.2 for all downloads.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Configure strict debugging.
Set-PSDebug -Strict

# if the agentName is empty, use %COMPUTERNAME% as the value
if ([String]::IsNullOrWhiteSpace($agentName))
{
    $agentName = $env:COMPUTERNAME
}

# if the agentNameSuffix has a value, add this to the end of the agent name
if (![String]::IsNullOrWhiteSpace($agentNameSuffix))
{
    $agentName = $agentName + $agentNameSuffix
}

###################################################################################################
#
# Handle all errors in this script.
#

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    $message = $Error[0].Exception.Message
    if ($message)
    {
        Write-Host -Object "`nERROR: $message" -ForegroundColor Red
    }

    Write-Host "`nThe artifact failed to apply.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

###################################################################################################
#
# Main execution block.
#

try
{
    # Ensure we set the working directory to that of the script.
    Push-Location $PSScriptRoot

    Write-Host 'Run'
    setx /M $name $value
}
finally
{
    Pop-Location
}