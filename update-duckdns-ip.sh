#!/bin/bash
# Script to update PostgreSQL security group with current Duck DNS IP
# This script automatically updates the security group when your Duck DNS IP changes

set -e

# Configuration
SECURITY_GROUP_ID="sg-0f9f0838cd3fd18cc"
REGION="us-east-1"
DUCK_DNS_DOMAIN="mock-fitband-api.duckdns.org"
PORT=5432

echo "============================================"
echo "Duck DNS IP Update for PostgreSQL Security Group"
echo "============================================"
echo ""

# Get current IP from Duck DNS
echo "Resolving Duck DNS domain: $DUCK_DNS_DOMAIN"
CURRENT_IP=$(dig +short $DUCK_DNS_DOMAIN | tail -n1)

if [ -z "$CURRENT_IP" ]; then
  echo "❌ Could not resolve IP for $DUCK_DNS_DOMAIN"
  echo "Check your internet connection and Duck DNS configuration"
  exit 1
fi

echo "Current Duck DNS IP: $CURRENT_IP"
echo ""

# Get all existing IPs for port 5432
EXISTING_IPS=$(aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`${PORT}\`].IpRanges[*].CidrIp" \
  --output text)

echo "Current security group rules for port $PORT:"
echo "$EXISTING_IPS" | tr '\t' '\n' | sed 's/^/  - /'
echo ""

# Check if current IP is already in security group
if echo "$EXISTING_IPS" | grep -q "${CURRENT_IP}/32"; then
  echo "✅ IP ${CURRENT_IP}/32 is already in security group rules"
  echo "No update needed."
  exit 0
fi

# Find and remove old Duck DNS IPs (any IP that's not a private IP range)
echo "Checking for old Duck DNS IPs to remove..."
for OLD_IP in $EXISTING_IPS; do
  # Remove /32 suffix
  IP=$(echo $OLD_IP | sed 's|/32||')
  
  # Check if it's not a private IP (10.x, 172.16-31.x, 192.168.x)
  if ! echo "$IP" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'; then
    # It's likely a public IP (could be old Duck DNS IP)
    if [ "$IP" != "$CURRENT_IP" ]; then
      echo "Removing old public IP: ${IP}/32"
      aws ec2 revoke-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port $PORT \
        --cidr ${IP}/32 \
        --region $REGION 2>/dev/null || echo "  (Rule may not exist, continuing...)"
    fi
  fi
done

# Add new IP
echo ""
echo "Adding new Duck DNS IP: ${CURRENT_IP}/32"
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port $PORT \
  --cidr ${CURRENT_IP}/32 \
  --region $REGION

echo ""
echo "✅ Security group updated successfully!"
echo "Duck DNS IP ${CURRENT_IP}/32 is now allowed to connect to PostgreSQL"

