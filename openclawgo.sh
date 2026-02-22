#!/bin/bash
# One-click OpenClaw deployment script. Runs setup_project,
# create_instance, waits for the VM, and remotely triggers
# install_openclaw.

set -e

# define color variables
GREEN='\033[92m'
NC='\033[0m'

source settings.conf

# confirm GCP project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
echo -e "\n${GREEN}Current GCP project: ${NC}${CURRENT_PROJECT}"
read -p "Deploy OpenClaw to this project? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Cancelled. Use 'gcloud config set project <PROJECT_ID>' to switch projects."
    exit 0
fi

# SSH setup
PUB_KEYS=(~/.ssh/*.pub)
if [[ ${#PUB_KEYS[@]} -eq 0 || ! -f "${PUB_KEYS[0]}" ]]; then
    echo -e "\n${GREEN}No SSH public keys found.${NC}"
    read -p "Generate a new SSH key pair? (y/N): " GEN_KEY
    if [[ "$GEN_KEY" != "y" && "$GEN_KEY" != "Y" ]]; then
        echo "An SSH key is required. Cancelled."
        exit 1
    fi
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
    PUB_KEYS=(~/.ssh/*.pub)
fi
if [[ ${#PUB_KEYS[@]} -gt 1 ]]; then
    while true; do
        echo -e "\n${GREEN}Which SSH public key would you like to use?${NC}"
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
    done
    PUB_KEYS=("${PUB_KEYS[$((KEY_CHOICE-1))]}")
fi
export PUB_KEY_FILE="${PUB_KEYS[0]}"
PRIVATE_KEY_FILE="${PUB_KEY_FILE%.pub}"
eval "$(ssh-agent -s)" > /dev/null 2>&1
ssh-add "$PRIVATE_KEY_FILE"

# setup project
echo -e "\n${GREEN}Setting up GCP project ...${NC}"
./setup_project.sh

# get static IP
IP_ADDRESS=$(gcloud compute addresses list --filter="name=${IP_NAME}" --format="value(address)")

# prompt user to set up DNS
echo -e "\n${GREEN}Static IP address: ${NC}${IP_ADDRESS}"
echo -e "Before continuing, add the following DNS A records at your domain registrar:"
echo -e "  openclaw.${DOMAIN} → ${IP_ADDRESS}"
echo -e "  litellm.${DOMAIN}  → ${IP_ADDRESS}"
echo ""
read -p "Press Enter when DNS records are in place ..."

# create instance (includes SSH key selection)
echo -e "\n${GREEN}Creating VM instance ...${NC}"
./create_instance.sh

# clear stale host key (VM was recreated at same IP)
echo -e "\n${GREEN}Clearing stale SSH host keys ...${NC}"
ssh-keygen -R ${IP_ADDRESS} 2>/dev/null || true

# wait for SSH
echo -e "\n${GREEN}Waiting for SSH to become available ...${NC}"
until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${USERNAME}@${IP_ADDRESS} true 2>/dev/null; do
    sleep 5
done

# wait for setup_instance.sh to finish
echo -e "\n${GREEN}Waiting for instance setup to complete ...${NC}"
until ssh ${USERNAME}@${IP_ADDRESS} "test -f /etc/firstboot" 2>/dev/null; do
    sleep 10
done

# run install_openclaw.sh remotely
echo -e "\n${GREEN}Running OpenClaw installation ...${NC}"
ssh -t -o ServerAliveInterval=30 ${USERNAME}@${IP_ADDRESS} "./install_openclaw.sh"

# clean up install files
echo -e "\n${GREEN}Cleaning up ...${NC}"
ssh ${USERNAME}@${IP_ADDRESS} "rm -f ~/install_openclaw.sh ~/settings.conf"

echo -e "\n${GREEN}OpenClaw deployment complete!${NC}"
echo -e "  OpenClaw: https://openclaw.${DOMAIN}"
echo -e "  LiteLLM:  https://litellm.${DOMAIN}"
