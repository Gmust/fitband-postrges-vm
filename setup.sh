#!/bin/bash
# Setup script for PostgreSQL VM
# Run this once on a fresh Azure VM (as root or with sudo)

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Setting up PostgreSQL VM...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Update system packages
echo -e "${BLUE}Updating system packages...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get update
    apt-get upgrade -y
    apt-get install -y curl wget git
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
    yum update -y
    yum install -y curl wget git
else
    echo -e "${YELLOW}Unsupported OS. Please install Docker manually.${NC}"
fi

# Install Docker
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}Installing Docker...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
else
    echo -e "${GREEN}Docker is already installed${NC}"
fi

# Install Docker Compose (standalone, if plugin not available)
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo -e "${BLUE}Installing Docker Compose...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Configure firewall - ONLY allow SSH and PostgreSQL from specific sources
if command -v ufw &> /dev/null; then
    echo -e "${BLUE}Configuring firewall...${NC}"
    ufw allow 22/tcp   # SSH
    # PostgreSQL port will be configured via Azure NSG for better security
    # ufw allow from <APP_VM_IP> to any port 5432  # Only from app VM
    ufw --force enable
    echo -e "${YELLOW}Note: Configure PostgreSQL port (5432) access via Azure NSG rules${NC}"
elif command -v firewall-cmd &> /dev/null; then
    echo -e "${BLUE}Configuring firewall (firewalld)...${NC}"
    firewall-cmd --permanent --add-service=ssh
    # PostgreSQL will be configured via Azure NSG
    firewall-cmd --reload
    echo -e "${YELLOW}Note: Configure PostgreSQL port (5432) access via Azure NSG rules${NC}"
fi

# Create backup directory
echo -e "${BLUE}Creating backup directory...${NC}"
mkdir -p /opt/postgres-vm/backups
chmod 755 /opt/postgres-vm/backups

echo -e "${GREEN}✓ PostgreSQL VM setup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy env.example to .env and configure it"
echo "2. Update POSTGRES_PASSWORD with a strong password"
echo "3. Configure Azure NSG to allow PostgreSQL access only from your app VM"
echo "4. Run: ./deploy.sh"

