#!/bin/bash
# This script copies scripts from a storage bucket into
# new OpenClaw instances and runs a few setup steps so that
# OpenClaw can be installed. This is run when an instance is
# created automatically by root before the user first logs
# in to the machine.


FIRST_BOOT_FLAG="/etc/firstboot"
if [ -f "$FIRST_BOOT_FLAG" ]; then
    exit 0
fi

# get settings variables
PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")

BUCKET_NAME="openclaw-scripts-bucket-${PROJECT_ID}"
source <(gcloud storage cat gs://${BUCKET_NAME}/settings.conf)
HOME_DIR=/home/$USERNAME


# download files
echo "Downloading files"
gcloud storage cp gs://$BUCKET_NAME/install_openclaw.sh $HOME_DIR/
gcloud storage cp gs://$BUCKET_NAME/.bashrc $HOME_DIR/
gcloud storage cp gs://$BUCKET_NAME/.vimrc $HOME_DIR/
gcloud storage cp gs://$BUCKET_NAME/.tmux.conf $HOME_DIR/
sudo -u $USERNAME mkdir -p $HOME_DIR/.config/litellm
gcloud storage cp gs://$BUCKET_NAME/litellm.env $HOME_DIR/.config/litellm/.env
gcloud storage cp gs://$BUCKET_NAME/litellm_config.yaml $HOME_DIR/.config/litellm/
gcloud storage cp gs://$BUCKET_NAME/ghostty.terminfo $HOME_DIR/
gcloud storage cp gs://$BUCKET_NAME/settings.conf $HOME_DIR/


# delete files
gcloud storage rm gs://$BUCKET_NAME/**


# fix permissions
echo "Fixing permissions"
chown -R $USERNAME:$USERNAME $HOME_DIR/install_openclaw.sh
chmod 744 $HOME_DIR/install_openclaw.sh
chown -R $USERNAME:$USERNAME $HOME_DIR/.bashrc
chown -R $USERNAME:$USERNAME $HOME_DIR/.vimrc
chown -R $USERNAME:$USERNAME $HOME_DIR/.tmux.conf
chown -R $USERNAME:$USERNAME $HOME_DIR/.config/litellm/.env
chmod 600 $HOME_DIR/.config/litellm/.env
chown -R $USERNAME:$USERNAME $HOME_DIR/.config/litellm/litellm_config.yaml
chown -R $USERNAME:$USERNAME $HOME_DIR/settings.conf


# terminfo
echo "Installing ghostty terminfo"
tic -x -o /usr/share/terminfo $HOME_DIR/ghostty.terminfo
rm $HOME_DIR/ghostty.terminfo


# create a 4GB swap space
echo "Creating swap space"
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab


# apt
rm -rf /var/lib/apt/lists/*
apt-get clean
apt-get update
apt-get -y upgrade
apt-get -y install build-essential git tmux tree


# sshd
echo "ClientAliveCountMax 20" >> /etc/ssh/sshd_config
systemctl restart ssh


# touch flag
touch $FIRST_BOOT_FLAG

