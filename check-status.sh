#!/bin/bash
# AWS CLI script to check PostgreSQL EC2 instance and database status

set -e

# Configuration
REGION="us-east-1"
INSTANCE_ID="i-02a876af693c45926"  # Your PostgreSQL instance ID
SECURITY_GROUP_ID="sg-0f9f0838cd3fd18cc"
KEY_FILE="${HOME}/.ssh/postgres-vm-key.pem"  # Adjust path to your key file

echo "============================================"
echo "PostgreSQL EC2 Status Check"
echo "============================================"
echo ""

# 1. Check EC2 Instance Status
echo "=== 1. EC2 Instance Status ==="
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' \
  --output table

# 2. Check Instance Health
echo ""
echo "=== 2. Instance Health Checks ==="
STATUS=$(aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status]' \
  --output text)

if [ -z "$STATUS" ]; then
  echo "Status checks: Not available (instance might be stopped)"
else
  echo "$STATUS" | awk '{print "Instance Status: " $1 "\nSystem Status: " $2}'
fi

# 3. Get IPs
echo ""
echo "=== 3. Network Information ==="
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

echo "Public IP:  $PUBLIC_IP"
echo "Private IP: $PRIVATE_IP"

# 4. Check Security Group Rules
echo ""
echo "=== 4. Security Group Rules ==="
aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP_ID \
  --region $REGION \
  --query 'SecurityGroups[0].IpPermissions[*].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
  --output table

# 5. Check if instance is running
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

if [ "$INSTANCE_STATE" != "running" ]; then
  echo ""
  echo "⚠️  Instance is not running (State: $INSTANCE_STATE)"
  echo "Cannot check PostgreSQL status. Start the instance first."
  exit 0
fi

# 6. Check PostgreSQL Status (via SSH)
echo ""
echo "=== 5. PostgreSQL Database Status ==="

if [ ! -f "$KEY_FILE" ]; then
  echo "⚠️  SSH key file not found at: $KEY_FILE"
  echo "Update KEY_FILE variable in this script with your key path"
  echo "Skipping PostgreSQL status check..."
  exit 0
fi

# Check if we can SSH
if ! ssh -i "$KEY_FILE" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "echo 'Connected'" 2>/dev/null; then
  echo "⚠️  Cannot SSH into instance. Check:"
  echo "   - Key file exists: $KEY_FILE"
  echo "   - Key permissions: chmod 400 $KEY_FILE"
  echo "   - Security group allows SSH from your IP"
  exit 0
fi

echo "Connecting to instance to check PostgreSQL..."

# Check Docker and PostgreSQL
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP << 'ENDSSH'
  echo ""
  echo "--- Docker Status ---"
  cd /opt/postgres-vm 2>/dev/null || { echo "⚠️  /opt/postgres-vm not found"; exit 1; }
  
  echo ""
  echo "PostgreSQL Container Status:"
  sudo docker-compose -f docker-compose.yml --env-file .env ps 2>/dev/null || sudo docker ps | grep postgres || echo "⚠️  PostgreSQL container not found"
  
  echo ""
  echo "--- Recent PostgreSQL Logs (last 10 lines) ---"
  sudo docker-compose -f docker-compose.yml --env-file .env logs --tail=10 postgres 2>/dev/null || echo "⚠️  Cannot read logs"
  
  echo ""
  echo "--- Database Connection Test ---"
  sudo docker-compose -f docker-compose.yml --env-file .env exec -T postgres \
    psql -U postgres -d mock_fitband_db -c "SELECT version();" 2>/dev/null && \
    echo "✅ Database connection successful" || \
    echo "⚠️  Cannot connect to database"
  
  echo ""
  echo "--- Database Size ---"
  sudo docker-compose -f docker-compose.yml --env-file .env exec -T postgres \
    psql -U postgres -d mock_fitband_db -c "SELECT pg_size_pretty(pg_database_size('mock_fitband_db'));" 2>/dev/null || echo "⚠️  Cannot get database size"
  
  echo ""
  echo "--- Active Connections ---"
  sudo docker-compose -f docker-compose.yml --env-file .env exec -T postgres \
    psql -U postgres -d mock_fitband_db -c "SELECT count(*) as active_connections FROM pg_stat_activity;" 2>/dev/null || echo "⚠️  Cannot get connection count"
ENDSSH

echo ""
echo "============================================"
echo "Status check complete!"
echo "============================================"

