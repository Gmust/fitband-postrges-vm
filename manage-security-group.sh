#!/bin/bash
# Script to manage PostgreSQL security group rules
# Add/remove IPs from PostgreSQL security group

set -e

# Configuration
SECURITY_GROUP_ID="sg-0f9f0838cd3fd18cc"
REGION="us-east-1"
PORT=5432

# PostgreSQL EC2 Instance Info
POSTGRES_INSTANCE_ID="i-02a876af693c45926"
POSTGRES_PRIVATE_IP="172.31.0.104"
POSTGRES_PUBLIC_IP="35.168.32.145"

# App EC2 Instance Info
APP_EC2_INSTANCE_ID="i-0fa3e17be45901cdb"
APP_EC2_PRIVATE_IP="172.31.79.89"
APP_EC2_PUBLIC_IP="35.175.136.111"

# Duck DNS
DUCK_DNS_DOMAIN="mock-fitband-api.duckdns.org"

show_help() {
  cat << EOF
PostgreSQL Security Group Manager

Usage: $0 [command] [options]

Commands:
  list                    List all current rules for port $PORT
  add <IP>                Add an IP address (CIDR format, e.g., 1.2.3.4/32)
  remove <IP>              Remove an IP address
  add-app-ec2             Add App EC2 private IP (recommended for production)
  add-app-ec2-public       Add App EC2 public IP
  add-duckdns              Add current Duck DNS IP
  add-local                Add your current local IP
  remove-local             Remove your current local IP
  show-all                 Show all IPs currently allowed

Examples:
  $0 list
  $0 add 1.2.3.4/32
  $0 remove 1.2.3.4/32
  $0 add-app-ec2
  $0 add-duckdns
  $0 add-local

Current Configuration:
  Security Group: $SECURITY_GROUP_ID
  Region: $REGION
  Port: $PORT
  PostgreSQL Instance: $POSTGRES_INSTANCE_ID ($POSTGRES_PRIVATE_IP)
  App EC2 Instance: $APP_EC2_INSTANCE_ID ($APP_EC2_PRIVATE_IP)
EOF
}

list_rules() {
  echo "Current security group rules for port $PORT:"
  echo ""
  aws ec2 describe-security-groups \
    --group-ids $SECURITY_GROUP_ID \
    --region $REGION \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`${PORT}\`].IpRanges[*].[CidrIp,Description]" \
    --output table
}

add_ip() {
  local IP=$1
  if [ -z "$IP" ]; then
    echo "❌ Error: IP address required"
    echo "Usage: $0 add <IP/CIDR>"
    exit 1
  fi
  
  echo "Adding IP: $IP"
  aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port $PORT \
    --cidr $IP \
    --region $REGION
  
  echo "✅ IP $IP added successfully"
}

remove_ip() {
  local IP=$1
  if [ -z "$IP" ]; then
    echo "❌ Error: IP address required"
    echo "Usage: $0 remove <IP/CIDR>"
    exit 1
  fi
  
  echo "Removing IP: $IP"
  aws ec2 revoke-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port $PORT \
    --cidr $IP \
    --region $REGION
  
  echo "✅ IP $IP removed successfully"
}

add_app_ec2() {
  echo "Adding App EC2 private IP: ${APP_EC2_PRIVATE_IP}/32"
  add_ip "${APP_EC2_PRIVATE_IP}/32"
}

add_app_ec2_public() {
  echo "Adding App EC2 public IP: ${APP_EC2_PUBLIC_IP}/32"
  add_ip "${APP_EC2_PUBLIC_IP}/32"
}

add_duckdns() {
  echo "Resolving Duck DNS domain: $DUCK_DNS_DOMAIN"
  CURRENT_IP=$(dig +short $DUCK_DNS_DOMAIN | tail -n1)
  
  if [ -z "$CURRENT_IP" ]; then
    echo "❌ Could not resolve IP for $DUCK_DNS_DOMAIN"
    exit 1
  fi
  
  echo "Current Duck DNS IP: $CURRENT_IP"
  add_ip "${CURRENT_IP}/32"
}

add_local() {
  echo "Getting your current public IP..."
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  
  if [ -z "$MY_IP" ]; then
    echo "❌ Could not determine your IP address"
    exit 1
  fi
  
  echo "Your IP: $MY_IP"
  add_ip "${MY_IP}/32"
}

remove_local() {
  echo "Getting your current public IP..."
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  
  if [ -z "$MY_IP" ]; then
    echo "❌ Could not determine your IP address"
    exit 1
  fi
  
  echo "Your IP: $MY_IP"
  remove_ip "${MY_IP}/32"
}

show_all() {
  echo "============================================"
  echo "PostgreSQL Security Group Rules"
  echo "============================================"
  echo ""
  echo "Security Group ID: $SECURITY_GROUP_ID"
  echo "Region: $REGION"
  echo "Port: $PORT"
  echo ""
  list_rules
  echo ""
  echo "Instance Information:"
  echo "  PostgreSQL EC2: $POSTGRES_INSTANCE_ID"
  echo "    Private IP: $POSTGRES_PRIVATE_IP"
  echo "    Public IP: $POSTGRES_PUBLIC_IP"
  echo ""
  echo "  App EC2: $APP_EC2_INSTANCE_ID"
  echo "    Private IP: $APP_EC2_PRIVATE_IP"
  echo "    Public IP: $APP_EC2_PUBLIC_IP"
}

# Main command handler
case "${1:-}" in
  list)
    list_rules
    ;;
  add)
    add_ip "$2"
    ;;
  remove)
    remove_ip "$2"
    ;;
  add-app-ec2)
    add_app_ec2
    ;;
  add-app-ec2-public)
    add_app_ec2_public
    ;;
  add-duckdns)
    add_duckdns
    ;;
  add-local)
    add_local
    ;;
  remove-local)
    remove_local
    ;;
  show-all)
    show_all
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "❌ Unknown command: ${1:-}"
    echo ""
    show_help
    exit 1
    ;;
esac

