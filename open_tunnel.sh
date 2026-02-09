#!/bin/bash
# Setup the remote for use with ghostty


source settings.conf

IP_ADDRESS=$(gcloud compute addresses list --filter="name=${IP_NAME}" --format="value(address)")

ssh -N -L 18789:127.0.0.1:18789 $IP_ADDRESS &
