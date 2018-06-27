#install Ansible
sudo apt-get update  && \
    apt-get install -y software-properties-common  && \
    apt-add-repository ppa:ansible/ansible  && \
    apt-get update  && \
    echo Y | apt-get install -y ansible python-pip   

# install Ansible Azure module
sudo apt-get install python-pip

sudo pip install ansible[azure]

# install az cli
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

sudo apt-get install apt-transport-https
sudo apt-get update && sudo apt-get install azure-cli
# clean
# sudo apt-get clean
