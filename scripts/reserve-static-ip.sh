#!/bin/bash

# Script to reserve a static IP address in GCP for SFTPGo
# Usage: ./reserve-static-ip.sh [IP_NAME] [REGION]

set -e

# Default values
IP_NAME="${1:-sftpgo-static-ip}"
REGION="${2:-asia-southeast1}"
PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"

echo "================================================"
echo "Reserving Static IP Address for SFTPGo"
echo "================================================"
echo "Project ID: $PROJECT_ID"
echo "IP Name: $IP_NAME"
echo "Region: $REGION"
echo "================================================"

# Check if IP already exists
if gcloud compute addresses describe "$IP_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
    echo "✓ Static IP '$IP_NAME' already exists"
    IP_ADDRESS=$(gcloud compute addresses describe "$IP_NAME" --region="$REGION" --project="$PROJECT_ID" --format="get(address)")
    echo "  IP Address: $IP_ADDRESS"
else
    echo "Creating new static IP address..."
    gcloud compute addresses create "$IP_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID"

    IP_ADDRESS=$(gcloud compute addresses describe "$IP_NAME" --region="$REGION" --project="$PROJECT_ID" --format="get(address)")
    echo "✓ Static IP created successfully"
    echo "  IP Address: $IP_ADDRESS"
fi

echo ""
echo "================================================"
echo "Next Steps:"
echo "================================================"
echo "1. Update k8s/service.yaml with the following annotation:"
echo "   cloud.google.com/load-balancer-type: \"External\""
echo "   loadBalancerIP: \"$IP_ADDRESS\""
echo ""
echo "2. Or set it as an environment variable:"
echo "   export SFTPGO_STATIC_IP=$IP_ADDRESS"
echo "================================================"

# Save IP to a file for later use
echo "$IP_ADDRESS" > .static-ip-address
echo "Static IP address saved to .static-ip-address"
