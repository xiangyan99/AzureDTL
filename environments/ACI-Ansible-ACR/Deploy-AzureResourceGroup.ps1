#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

<#
  .SYNOPSIS
  Deploy an Azure resource group template.
  .PARAMETER ResourceGroupLocation
  The location of the target resource group.
  .PARAMETER ResourceGroupName
  The name of the target resource group.
  .PARAMETER StorageAccountName
  The name of the storage account used to stage artifacts.
  .PARAMETER StorageContainerName
  The name of the storage container used to stage artifacts.
  .PARAMETER TemplateFile
  The name / path of the ARM template file to deploy.
  .PARAMETER ParameterFile
  The name / path of the ARM parameters file to deploy.
  .PARAMETER ArtifactDirectory
  The name / path of the directory containing deployment artifacts.
  .PARAMETER UploadArtifacts
  Flag to enforce an artifacts upload.
  .PARAMETER UploadParallel
  Flag to enable artifact uploading in parallel.
  .PARAMETER ValidateOnly
  Flag to validate the ARM template instead of deploying it.
  .PARAMETER Reset
  Flag to reset the target resource group before the deployment.
  .PARAMETER Force
  Flag to cancel all running deployments on the target resource group.
  .PARAMETER VSTS
  Flag to enable VSTS integration (deployment output will become VSTS variables). 
  .PARAMETER VSTSPrefix
  VSTS variable prefix to use when VSTS flag is set. 
#>

Param(
    
    [Parameter(Mandatory = $true)] 
    [string] $ResourceGroupLocation,

    [Parameter(Mandatory = $true)] 
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $false)] 
    [string] $StorageAccountName = 'stage' + ((Get-AzureRmContext).Subscription.Id).Replace('-', '').substring(0, 19),

    [Parameter(Mandatory = $false)] 
    [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts-' + (Get-Date).Ticks,

    [Parameter(Mandatory = $false)] 
    [string] $TemplateFile = 'azuredeploy.json',

    [Parameter(Mandatory = $false)] 
    [string] $ParameterFile = 'azuredeploy.parameters.json',

    [Parameter(Mandatory = $false)] 
    [string] $ArtifactDirectory = '.',

    [switch] $UploadArtifacts,
    [switch] $UploadParallel,
    [switch] $ValidateOnly,
    [switch] $Reset,
    [switch] $Force,
    [switch] $VSTS,

    [Parameter(Mandatory = $false)] 
    [string] $VSTSPrefix = '',

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]] $ParameterOverrides
)

trap {

    $message = $error[0].Exception.Message
    
    if ($message) {

        Write-Error "`n$message"
    }
}

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(' ', '_'), '3.0.0')
}
catch { }

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Format-ValidationOutput {
    param ($ValidationOutput, [int] $Depth = 0)
    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}

function Write-OutputHeader {
    param ([string] $Title)
    $seperatorLine = (@('=') * ((100, $Title.Length) | Measure-Object -Maximum).Maximum) -join ''
    Write-Output '', $seperatorLine, $Title, $seperatorLine, ''
}

function Export-AzureRmContextFile {
    $ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx')
    if (Test-Path $ContextPath -PathType Leaf) { Remove-Item -Path $ContextPath -Force | Out-Null }
    $ContextClassic = [bool] (Get-Command -Name Save-AzureRmProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
    if ($ContextClassic) { Save-AzureRmProfile -Path $ContextPath } else { Save-AzureRmContext -Path $ContextPath -Force }
    return $ContextPath
}

function Import-AzureRmContextFile {
    param([string] $ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx'))
    $ContextClassic = [bool] (Get-Command -Name Select-AzureRMProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
    if ($contextClassic) { Select-AzureRMProfile -Path $ContextPath } else { Import-AzureRmContext -Path $ContextPath }
}

function Get-TemplateParameters {
    param ([string] $TemplateFile, [string] $ParameterFile)

    $templateJson = Get-Content $TemplateFile -Raw | ConvertFrom-Json
    $parameterJson = $null

    if ($ParameterFile) {

        $parameterJson = Get-Content $ParameterFile -Raw | ConvertFrom-Json
    }
    
    $parameters = @()

    $templateJson.parameters | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {

        $parameter = New-Object -TypeName psobject | Add-Member -MemberType NoteProperty -Name "Name" -Value "$_" -PassThru |
                                                     Add-Member -MemberType NoteProperty -Name "UnifiedName" -Value "$($_ -replace ' ', '')" -PassThru |
                                                     Add-Member -MemberType NoteProperty -Name "Type" -Value "$($templateJson.parameters.$_.type)" -PassThru |
                                                     Add-Member -MemberType NoteProperty -Name "Optional" -Value "$( [bool] ($templateJson.parameters.$_ | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -eq 'defaultValue' }))" -PassThru |
                                                     Add-Member -MemberType NoteProperty -Name "Value" -Value ([object] $null) -PassThru 

        if ($parameterJson -and (($parameterJson.parameters | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -contains "$_")) {

            $parameter.Value = ConvertTo-ParameterValue -ParameterType $parameter.Type -ParameterValue $parameterJson.parameters.$_.value
        }

        $parameters += $parameter
    }

    return $parameters
}

function ConvertTo-ParameterValue {
    param ([ValidateSet('array', 'bool', 'int', 'object', 'secureobject', 'securestring', 'string')][string] $ParameterType, $ParameterValue)
    if ($ParameterValue -ne $null) {
        switch ($ParameterType) {
            'array' {  
                if ($ParameterValue -is [array]) {
                    return $ParameterValue
                } else {
                    $ParameterValueString = $ParameterValue.ToString()
                    if ($ParameterValueString.StartsWith('[') -and $ParameterValueString.EndsWith(']')) {
                        return [array] $ParameterValueString | ConvertFrom-Json
                    } else {
                        return [array] (($ParameterValueString -split ',') | ForEach-Object { $_.Trim() })
                    }
                } 
            }
            'bool' {  
                if ($ParameterValue -is [bool]) {
                    return $ParameterValue
                } else {
                    return [bool] ([System.Xml.XmlConvert]::ToBoolean("$ParameterValue"))
                }
            }
            'int' {  
                if ($ParameterValue -is [int]) {
                    return $ParameterValue
                } else {
                    return ([int]::Parse($ParameterValue.ToString()))
                }
            }
            'object' {  
                if ($ParameterValue -is [string]) {
                    return ($ParameterValue | ConvertFrom-Json)
                } else {
                    return $ParameterValue
                }
            }
            'securestring' {  
                if ($ParameterValue -is [securestring]) {
                    return $ParameterValue
                } else {
                    return (ConvertTo-SecureString -AsPlainText -Force ($ParameterValue.ToString()))
                }
            }
            'string' { 
                return $ParameterValue.ToString()
            }
            default {  
                throw "Not implemented - The parameter type '$ParameterType' is currently not supported"
            }
        }
    }

    return $null
}

function ConvertTo-TemplateParameterHashTable {
    param ([object[]] $Parameters)
    $hashtable = New-Object -TypeName hashtable
    $Parameters | Where-Object { $_.Value -ne $null } | ForEach-Object { $hashtable[$_.Name] = $_.Value }
    return $hashtable
}

function ConvertTo-AzureDevOptsVariables {
    param ([hashtable] $deploymentOutputs)

    $variables = @()

    if ($deploymentOutputs) {

        $deploymentOutputs.Keys | ForEach-Object {

            $value = $deploymentOutputs["$_"].value

            if ($value -is [object]) {

                # serialize object to json
                $value = $value | ConvertTo-Json -Compress
            }

            $variables += New-Object -TypeName psobject | Add-Member -MemberType NoteProperty -Name "Name" -Value "$VSTSPrefix$_" -PassThru |
                                                          Add-Member -MemberType NoteProperty -Name "Value" -Value "$value" -PassThru
        }
    }

    return $variables
}

function Format-TemplateParameterOutput {
    param ([object[]] $Parameters)

    return $Parameters | Format-Table Name, Type, @{
        
        L = 'Value'

        E = {
            if ($_.Type -like 'secure*') { 
                '*****' 
            }
            elseif ( $_.Value -ne $null ) {
                $_.Value
            }
            elseif ( $_.Optional ) {
                '[defaultValue]'
            }
            else { 
                '[missingValue]' 
            }
        }

    } | Out-String
}

function Merge-TemplateParameterOverrides {
    param ([object[]] $Parameters, [object[]] $Overrides)

    $overridePrefix = '-ARM_'

    if (($Overrides.Count % 2) -ne 0) {

        # Override parameters need to be provided as pairs
        throw "Malformed parameter overrides"
    }

    $key = [string] $null

    for ($i = 0; $i -lt $Overrides.Count; $i++) {
        
        $override = $Overrides[$i]

        if (($i % 2) -eq 0) {

            if (-not $override.ToString().StartsWith($overridePrefix)) {

                # The override parameter name needs to be prefixed
                throw "Malformed parameter overrides - parameter names need a '$overridePrefix' prefix" 

            } else {

                # Remove the key prefix for further processing
                $key = $override.ToString().Substring($overridePrefix.Length)
            }

        } else {

            $parameter = $Parameters | Where-Object { $_.UnifiedName -eq $key } | Select-Object -First 1

            if ($parameter) {

                $parameter.Value = ConvertTo-ParameterValue -ParameterType $parameter.Type -ParameterValue $override

            } else {

                # The target parameter name is out of bounds
                throw "Could not find parameter with name '$key'"
            }
        }
    }
}

$ContextFile = Export-AzureRmContextFile

try {

    $TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))

    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {

        # Template file not found
        Write-Error "Could not find template file '$TemplateFile'" -ErrorAction Stop
    }

    $ParameterFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ParameterFile))

    if (-not (Test-Path -Path $ParameterFile -PathType Leaf)) {

        # Parameter file not found
        $ParameterFile = $null
    }

    $ArtifactDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactDirectory))

    if (-not (Test-Path -Path $ArtifactDirectory -PathType Container)) {

        # Artifact directory not found
        Write-Error "Could not find artifact directory '$ArtifactDirectory'" -ErrorAction Stop
    }

    $ArtifactsLocationName = '_artifactsLocation'
    $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'

    $Parameters = Get-TemplateParameters -TemplateFile $TemplateFile -ParameterFile $ParameterFile

    if ($ParameterOverrides) { 

        # merge command line parameter overrides into parameter set
        Merge-TemplateParameterOverrides -Parameters $Parameters -Overrides $ParameterOverrides
    }

    if ($UploadArtifacts -or ($Parameters -and ($Parameters | Where-Object { $_.Name -in ($ArtifactsLocationName, $ArtifactsLocationSasTokenName) }))) {

        Write-OutputHeader -Title 'Upload artifacts'

        # Get the storage account for artifact upload
        $StorageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $StorageAccountName})

        # Create the storage account if it doesn't already exist
        if (-not $StorageAccount) {
            $StorageResourceGroupName = 'ARM_Deploy_Staging'
            New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $StorageResourceGroupName -Force | Out-Null
            $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location "$ResourceGroupLocation"
        }

        # Create the storage contianer if it doesn't already exist
        New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue | Out-Null

        if ($UploadParallel) {

            # Upload artifacts in parallel
            $jobs = (Get-ChildItem $ArtifactDirectory -Recurse -File | Select-Object -ExpandProperty FullName | Where-Object { -not ($_ -in ($PSCommandPath, $ContextFile)) } | ForEach-Object {
                Start-Job -Name "$_" -ScriptBlock {
                    param([string] $ctxFile, [string] $sourceFile, [string] $targetFile, [string] $storageName, [string] $containerName)
                    $ContextClassic = [bool] (Get-Command -Name Select-AzureRMProfile -ErrorAction SilentlyContinue)
                    if  ($ContextClassic) { Select-AzureRMProfile -Path $ctxFile } else { Import-AzureRmContext -Path $ctxFile }
                    $StorageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageName})
                    Set-AzureStorageBlobContent -File $sourceFile -Blob $targetFile -Container $containerName -Context $StorageAccount.Context -Force | Out-Null
                } -ArgumentList ($ContextFile, $_, ($_.Substring($ArtifactDirectory.length + 1)), $StorageAccountName, $StorageContainerName)
            }) 

            if ($jobs) {

                # wait for upload jobs to be done
                $jobs | % -Process { Write-Output "Uploading artifact -> $($_.Name) ..." } -End { Write-Output "" }
                $jobs | Wait-Job | Out-Null
            
                $jobs | % {
                    if ( $_.State -eq "Failed" ) {
                        Write-Error ($_.ChildJobs[0].JobStateInfo.Reason.Message) -ErrorAction Stop
                    } else {
                        Write-Output "Uploaded artifact -> $($_.Name) [$($_.State)]"
                    }                
                }
            }

        } else {

            (Get-ChildItem $ArtifactDirectory -Recurse -File | Select-Object -ExpandProperty FullName | Where-Object { -not ($_ -in ($PSCommandPath, $ContextFile)) }) | % {

                Write-Output "Uploading artifact -> $_ ..."
                Set-AzureStorageBlobContent -File $_ -Blob $_.Substring($ArtifactDirectory.length + 1) -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
            }
        }

        # Update artifact related parameters
        foreach ($param in $Parameters) {
            switch ($param.Name) {
                "$ArtifactsLocationName"            { $param.Value = (ConvertTo-ParameterValue -ParameterType ($param.Type) -ParameterValue ($StorageAccount.Context.BlobEndPoint + $StorageContainerName)) }
                "$ArtifactsLocationSasTokenName"    { $param.Value = (ConvertTo-ParameterValue -ParameterType ($param.Type) -ParameterValue (New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))) }
            }
        }
    }

    # Get the target resource group if exists
    $resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($Force -and $resourceGroup) {

        Write-OutputHeader -Title "Stop running deployments for resource group '$ResourceGroupName'"
        Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName | ? { $_.ProvisioningState -eq "Running" } | Stop-AzureRmResourceGroupDeployment -Verbose 
    }

    if ($Reset -and $resourceGroup) {

        $location = Get-AzureRmLocation | Where-Object { $_.Location -eq $ResourceGroupLocation -or $_.DisplayName -eq $ResourceGroupLocation } | Select-Object -First 1

        if ($resourceGroup.Location -eq $location.Location) {

            Write-OutputHeader -Title "Delete existing deployments"
            Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName | ForEach-Object {
                Write-Output "Deleting deployment -> $($_.DeploymentName)"
                $_ | Remove-AzureRmResourceGroupDeployment | Out-Null
            }

            Write-OutputHeader -Title "Reset resource group '$ResourceGroupName'"
            $resetDeploymentName = 'azurereset-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')
            $resetTemplateFile = Join-Path $PSScriptRoot "azurereset.json"

            if (Test-Path -Path $resetTemplateFile -PathType Leaf ) {

                New-AzureRmResourceGroupDeployment -Name $resetDeploymentName `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateFile $resetTemplateFile
                    -TemplateParameterUri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/100-blank-template/azuredeploy.parameters.json" `
                    -Force -Verbose -Mode Complete

            } else {

                New-AzureRmResourceGroupDeployment -Name $resetDeploymentName `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateUri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/100-blank-template/azuredeploy.json" `
                    -TemplateParameterUri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/100-blank-template/azuredeploy.parameters.json" `
                    -Force -Verbose -Mode Complete
            }

        } else {

            Write-OutputHeader -Title "Delete resource group '$ResourceGroupName'"
            $resourceGroup | Remove-AzureRmResourceGroup -Force -Verbose
            $resourceGroup = $null
        }
    }

    if (-not $resourceGroup) {

        Write-OutputHeader -Title "Create resource group '$ResourceGroupName'"
        $resourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force
    }

    Write-OutputHeader "Deployment parameters"
    Write-Output (Format-TemplateParameterOutput -Parameters $Parameters)

    $deploymentParameters = [hashtable] (ConvertTo-TemplateParameterHashTable -Parameters $Parameters)

    if ($ValidateOnly) {

        Write-OutputHeader "Validate ARM template"

        $ErrorMessages = Format-ValidationOutput (Test-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                -TemplateFile $TemplateFile `
                @deploymentParameters)

        if ($ErrorMessages) {
            Write-Output '', 'Validation returned the following errors:', @($ErrorMessages), '', 'Template is invalid.'
        } else {
            Write-Output '', 'Template is valid.'
        }
    }
    else 
    {

        Write-OutputHeader -Title "Deploy ARM template to resource group '$ResourceGroupName'"

        $deploymentResult = $null # captures the deployment result

        New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $TemplateFile `
            @deploymentParameters `
            -Force -Verbose -Mode Complete `
            -ErrorVariable ErrorMessages | Tee-Object -Variable deploymentResult
                                        
        if ($ErrorMessages) {

            Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
        
        } elseif ($VSTS -and $deploymentResult.outputs) {

            Write-OutputHeader "Publish VSTS variables"

            $variables = ConvertTo-AzureDevOptsVariables -deploymentOutputs $deploymentResult.outputs
            $variables | Format-Table

            $variables | ForEach-Object {

                Write-Output ("##vso[task.setvariable variable=$($_.Name);]$($_.Value)")
            }
        }
    }
}
finally {

    # clean up temp files
    Remove-Item -Path $ContextFile -Force -ErrorAction SilentlyContinue | Out-Null
} 