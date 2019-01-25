#!/bin/sh

trace() {
    TRACE_DATE=$(date '+%F %T.%N')
    echo ">>> $TRACE_DATE: $@"
}

trace "Envs: EnvironmentResourceGroupName=$EnvironmentResourceGroupName"
trace "Envs: EnvironmentDeploymentName=$EnvironmentDeploymentName"
trace "Envs: ContainerGroupId=$ContainerGroupId"

trace "Setup folder structure ..."
mkdir /playbooks && cd /playbooks

trace "Downloading playbooks ..."
for url in $*; do wget ${url}; done

trace "Cleanup playbooks ..."
for file in $(find -type f -name "*\?*"); do mv $file $(echo $file | cut -d? -f1); done

trace "Connecting Azure ..."
while true; do
    trace "Connecting Azure ..."
    # managed identity isn't avaialble directly - retry
    az login --identity 2>/dev/null && {
        export ARM_USE_MSI=true
        export ARM_MSI_ENDPOINT='http://169.254.169.254/metadata/identity/oauth2/token'
        export ARM_SUBSCRIPTION_ID=$(az account show --output=json | jq -r -M '.id')
        break
    } || sleep 5    
done

export ANSIBLE_AZURE_AUTH_SOURCE=msi

trace "Wait for Azure deployment ..."
az group deployment wait --resource-group $EnvironmentResourceGroupName --name $EnvironmentDeploymentName --created

trace "Run Ansible Playbook ..."
ansible-playbook azuredeploy.yml --extra-vars "resource_group=$EnvironmentResourceGroupName AZURE_SUBSCRIPTION_ID=$ARM_SUBSCRIPTION_ID"

if [ -z "$ContainerGroupId" ]; then
    trace "Waiting for termination ..."
    tail -f /dev/null
else
    trace "Deleting container groups ..."
    az container delete --yes --ids $ContainerGroupId
fi
