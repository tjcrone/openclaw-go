#!/bin/bash
# Done once per OpenClaw project. This assumes you are logged
# in to the project using `gcloud auth login` and `gcloud config
# set project [PROJECT_ID]`.

set -e

# define color variables
GREEN='\033[92m'
NC='\033[0m' # reset color

source settings.conf

# enable APIs
echo -e "\n${GREEN}Enabling APIs ...${NC}"
gcloud services enable compute.googleapis.com storage.googleapis.com --async
sleep 10

# create custom network
if ! gcloud compute networks describe $NET_NAME > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating network $NET_NAME ...${NC}"
    gcloud compute networks create $NET_NAME --subnet-mode=custom --bgp-routing-mode=regional
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$NET_NAME --region=$REGION --range=10.0.0.0/24
fi

# create firewall rules
if ! gcloud compute firewall-rules describe openclaw-allow-ssh > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating firewall rule openclaw-allow-ssh ...${NC}"
    gcloud compute firewall-rules create openclaw-allow-ssh \
        --network=$NET_NAME --action=ALLOW --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 --target-tags=openclaw-instance
fi

if ! gcloud compute firewall-rules describe openclaw-allow-https > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating firewall rule openclaw-allow-https ...${NC}"
    gcloud compute firewall-rules create openclaw-allow-https \
        --network=$NET_NAME --action=ALLOW --rules=tcp:80,tcp:443 \
        --source-ranges=0.0.0.0/0 --target-tags=openclaw-instance
fi

# create service account
if ! gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating service account $SA_NAME ...${NC}"
    gcloud iam service-accounts create $SA_NAME --display-name "OpenClaw Service Account"

    echo -e "\n${GREEN}Waiting for service account to propagate ...${NC}"
    until gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; do
        sleep 2
    done
fi

# grant IAM roles
echo -e "\n${GREEN}Granting IAM roles to $SA_EMAIL ...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.objectAdmin" > /dev/null

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/logging.logWriter" > /dev/null

# create storage bucket
if ! gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
    echo -e "\n${GREEN}Creating storage bucket $BUCKET_NAME ...${NC}"
    gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION
fi

# reserve static IP
if ! gcloud compute addresses describe $IP_NAME --region=$REGION > /dev/null 2>&1; then
    echo -e "\n${GREEN}Reserving static IP $IP_NAME ...${NC}"
    gcloud compute addresses create $IP_NAME --region=$REGION
fi

# project metadata
echo -e "\n${GREEN}Setting project metadata ...${NC}"
gcloud compute project-info add-metadata \
    --metadata enable-oslogin=FALSE,startup-script-url=gs://$BUCKET_NAME/$SETUP_SCRIPT

echo -e "\n${GREEN}Project setup complete.${NC}"

