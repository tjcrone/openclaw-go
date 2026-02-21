#!/bin/bash
# Done once per new OpenClaw VM. Assumes you are logged in
# to the project using gcloud auth.

set -e

# define color variables
GREEN='\033[92m'
NC='\033[0m' # reset color

# source the settings file
source settings.conf

# find SSH public keys
PUB_KEYS=(~/.ssh/*.pub)
if [[ ${#PUB_KEYS[@]} -eq 0 ]]; then
    echo "No SSH public keys found in ~/.ssh/"
    exit 1
elif [[ ${#PUB_KEYS[@]} -eq 1 ]]; then
    PUB_KEY_FILE="${PUB_KEYS[0]}"
else
    while true; do
        echo "Which SSH public key would you like to use?"
        for i in "${!PUB_KEYS[@]}"; do
            echo "  $((i+1))) ${PUB_KEYS[$i]##*/}"
        done
        echo "  q) Quit"
        read -p "Select a key (1-${#PUB_KEYS[@]}, q): " KEY_CHOICE
        if [[ "$KEY_CHOICE" == "q" || "$KEY_CHOICE" == "Q" ]]; then
            echo "Cancelled."
            exit 0
        fi
        if [[ "$KEY_CHOICE" =~ ^[0-9]+$ && "$KEY_CHOICE" -ge 1 && "$KEY_CHOICE" -le ${#PUB_KEYS[@]} ]]; then
            break
        fi
        echo "Invalid selection. Please try again."
        echo ""
    done
    PUB_KEY_FILE="${PUB_KEYS[$((KEY_CHOICE-1))]}"
fi
SSH_KEY="${USERNAME}:$(cat "$PUB_KEY_FILE")"


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
        --metadata=startup-script-url=gs://$BUCKET_NAME/$SETUP_SCRIPT,ssh-keys="$SSH_KEY"
fi

echo -e "\n${GREEN}OpenClaw machine creation complete.${NC}"
