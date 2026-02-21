#!/bin/bash
# Tears down everything created by setup_project.sh.
# Reverses operations in dependency order.

set -e

source settings.conf

# confirm teardown
echo -e "\n${GREEN}You are about to tear down project: $PROJECT_ID${NC}"
read -p "Are you sure you want to proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Teardown cancelled."
    exit 0
fi


# remove project metadata
echo "Removing project metadata ..."
gcloud compute project-info remove-metadata \
    --keys=enable-oslogin,startup-script-url


# release static IP
if gcloud compute addresses describe $IP_NAME --region=$REGION > /dev/null 2>&1; then
    echo "Deleting static IP $IP_NAME ..."
    gcloud compute addresses delete $IP_NAME --region=$REGION --quiet
fi


# delete storage bucket
if gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
    echo "Deleting storage bucket $BUCKET_NAME ..."
    gcloud storage rm -r gs://$BUCKET_NAME
fi


# revoke IAM roles from service account
if gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; then
    IAM_POLICY=$(gcloud projects get-iam-policy $PROJECT_ID --format=json)

    if echo "$IAM_POLICY" | jq -e '.bindings[] | select(.role=="roles/logging.logWriter") | .members[] | select(.=="serviceAccount:'$SA_EMAIL'")' > /dev/null 2>&1; then
        echo "Revoking roles/logging.logWriter from $SA_EMAIL ..."
        gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/logging.logWriter" > /dev/null
    fi

    if echo "$IAM_POLICY" | jq -e '.bindings[] | select(.role=="roles/storage.objectAdmin") | .members[] | select(.=="serviceAccount:'$SA_EMAIL'")' > /dev/null 2>&1; then
        echo "Revoking roles/storage.objectAdmin from $SA_EMAIL ..."
        gcloud projects remove-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/storage.objectAdmin" > /dev/null
    fi

    # delete service account
    echo "Deleting service account $SA_NAME ..."
    gcloud iam service-accounts delete $SA_EMAIL --quiet
fi


# delete firewall rules
if gcloud compute firewall-rules describe openclaw-allow-ssh > /dev/null 2>&1; then
    echo "Deleting firewall rule openclaw-allow-ssh ..."
    gcloud compute firewall-rules delete openclaw-allow-ssh --quiet
fi


# delete subnet and network
if gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION > /dev/null 2>&1; then
    echo "Deleting subnet $SUBNET_NAME ..."
    gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet
fi

if gcloud compute networks describe $NET_NAME > /dev/null 2>&1; then
    echo "Deleting network $NET_NAME ..."
    gcloud compute networks delete $NET_NAME --quiet
fi


# disable APIs
echo "Disabling APIs ..."
gcloud services disable storage.googleapis.com --force
gcloud services disable compute.googleapis.com --force

echo "Teardown complete."
