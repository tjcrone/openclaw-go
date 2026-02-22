#!/bin/bash
# Tears down everything created by setup_project.sh.
# Reverses operations in dependency order.

set -e

# define color variables
GREEN='\033[92m'
NC='\033[0m' # reset color

source settings.conf

# confirm teardown
echo -e "\n${GREEN}You are about to tear down project: $PROJECT_ID${NC}"
read -p "Are you sure you want to proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Teardown cancelled."
    exit 0
fi


# delete VM
if gcloud compute instances describe $VM_NAME --zone=$ZONE > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting VM $VM_NAME ...${NC}"
    gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
fi


# remove project metadata
echo -e "\n${GREEN}Removing project metadata ...${NC}"
gcloud compute project-info remove-metadata \
    --keys=enable-oslogin,startup-script-url


# release static IP
if gcloud compute addresses describe $IP_NAME --region=$REGION > /dev/null 2>&1; then
    read -p "Keep static IP address (to preserve DNS records)? (Y/n): " KEEP_IP
    if [[ "$KEEP_IP" == "n" || "$KEEP_IP" == "N" ]]; then
        echo -e "\n${GREEN}Deleting static IP $IP_NAME ...${NC}"
        gcloud compute addresses delete $IP_NAME --region=$REGION --quiet
    else
        echo -e "${GREEN}Keeping static IP $IP_NAME.${NC}"
    fi
fi


# delete storage bucket
if gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting storage bucket $BUCKET_NAME ...${NC}"
    gcloud storage rm -r gs://$BUCKET_NAME
fi


# revoke IAM roles from service account
if gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; then
    IAM_POLICY=$(gcloud projects get-iam-policy $PROJECT_ID --format=json)

    if echo "$IAM_POLICY" | jq -e '.bindings[] | select(.role=="roles/logging.logWriter") | .members[] | select(.=="serviceAccount:'$SA_EMAIL'")' > /dev/null 2>&1; then
        echo -e "\n${GREEN}Revoking roles/logging.logWriter from $SA_EMAIL ...${NC}"
        gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/logging.logWriter" > /dev/null
    fi

    if echo "$IAM_POLICY" | jq -e '.bindings[] | select(.role=="roles/storage.objectAdmin") | .members[] | select(.=="serviceAccount:'$SA_EMAIL'")' > /dev/null 2>&1; then
        echo -e "\n${GREEN}Revoking roles/storage.objectAdmin from $SA_EMAIL ...${NC}"
        gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/storage.objectAdmin" > /dev/null
    fi

    # delete service account
    echo -e "\n${GREEN}Deleting service account $SA_NAME ...${NC}"
    gcloud iam service-accounts delete $SA_EMAIL --quiet
fi


# delete firewall rules
if gcloud compute firewall-rules describe openclaw-allow-https > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting firewall rule openclaw-allow-https ...${NC}"
    gcloud compute firewall-rules delete openclaw-allow-https --quiet
fi

if gcloud compute firewall-rules describe openclaw-allow-ssh > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting firewall rule openclaw-allow-ssh ...${NC}"
    gcloud compute firewall-rules delete openclaw-allow-ssh --quiet
fi


# delete subnet and network
if gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting subnet $SUBNET_NAME ...${NC}"
    gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet
fi

if gcloud compute networks describe $NET_NAME > /dev/null 2>&1; then
    echo -e "\n${GREEN}Deleting network $NET_NAME ...${NC}"
    gcloud compute networks delete $NET_NAME --quiet
fi


# disable APIs
echo -e "\n${GREEN}Disabling APIs ...${NC}"
gcloud services disable storage.googleapis.com --force
gcloud services disable compute.googleapis.com --force

echo -e "\n${GREEN}Teardown complete.${NC}"
