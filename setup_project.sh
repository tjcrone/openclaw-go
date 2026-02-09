#!/bin/bash
# Done once per OpenClaw project. This assumes you are logged
# in to the project using `gcloud auth login` and `gcloud config
# set project [PROJECT_ID]`.

set -e

source settings.conf

# enable APIs
gcloud services enable compute.googleapis.com storage.googleapis.com

# create custom network
if ! gcloud compute networks describe $NET_NAME > /dev/null 2>&1; then
    gcloud compute networks create $NET_NAME --subnet-mode=custom --bgp-routing-mode=regional
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$NET_NAME --region=$REGION --range=10.0.0.0/24
fi

# create firewall rules
if ! gcloud compute firewall-rules describe openclaw-allow-ssh > /dev/null 2>&1; then
    gcloud compute firewall-rules create openclaw-allow-ssh \
        --network=$NET_NAME --action=ALLOW --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 --target-tags=openclaw-instance
fi

# create service account
if ! gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; then
    gcloud iam service-accounts create $SA_NAME --display-name "OpenClaw Service Account"
fi

# grant storage permission
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.objectAdmin" > /dev/null

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/logging.logWriter" > /dev/null

# create storage bucket
if ! gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
    gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION
fi

# reserve static IP
if ! gcloud compute addresses describe $IP_NAME --region=$REGION > /dev/null 2>&1; then
    gcloud compute addresses create $IP_NAME --region=$REGION
fi

# project metadata
gcloud compute project-info add-metadata \
    --metadata enable-oslogin=FALSE,startup-script-url=gs://$BUCKET_NAME/$SETUP_SCRIPT

