apt-get update  && \
    apt-get install -y software-properties-common  && \
    apt-add-repository ppa:ansible/ansible  && \
    apt-get update  && \
    echo Y | apt-get install -y ansible

apt-get install -y sshpass openssh-client

pip install --upgrade pip

# install Azure, aws, gce, Rackspace, CloudStack dependencies
pip install ansible[azure] \
    boto \
    apache-libcloud \
    pyrax \
    cs

# clean
apt-get clean
