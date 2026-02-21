#!/bin/bash
# Done once per new OpenClaw VM. Assumes you are logged in
# to the project using gcloud auth.

set -e

# define color variables
GREEN='\033[92m'
NC='\033[0m' # reset color

# source the settings file
source settings.conf


# copy files to bucket
echo -e "\n${GREEN}Copying files to the OpenClaw bucket $BUCKET_NAME ...${NC}"
gcloud storage cp ./install_openclaw.sh gs://$BUCKET_NAME
gcloud storage cp ./$SETUP_SCRIPT gs://$BUCKET_NAME
gcloud storage cp ./.bashrc gs://$BUCKET_NAME
gcloud storage cp ./.vimrc gs://$BUCKET_NAME
gcloud storage cp ./.tmux.conf gs://$BUCKET_NAME
gcloud storage cp ./litellm.env gs://$BUCKET_NAME
gcloud storage cp ./litellm_config.yaml gs://$BUCKET_NAME
gcloud storage cp ./ghostty.terminfo gs://$BUCKET_NAME
gcloud storage cp ./settings.conf gs://$BUCKET_NAME


# create the VM
if ! gcloud compute instances describe $VM_NAME --zone=$ZONE > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating OpenClaw VM $VM_NAME ...${NC}"
    gcloud compute instances create $VM_NAME \
        --zone=$ZONE \
        --machine-type=$MACHINE_TYPE \
        --image-family=debian-13 \
        --image-project=debian-cloud \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-balanced \
        --network=$NET_NAME \
        --subnet=$SUBNET_NAME \
        --address=$IP_NAME \
        --service-account=$SA_EMAIL \
        --scopes=cloud-platform \
        --tags=openclaw-instance \
        --metadata=startup-script-url=gs://$BUCKET_NAME/$SETUP_SCRIPT
fi

echo -e "\n${GREEN}OpenClaw machine creation complete.${NC}"
