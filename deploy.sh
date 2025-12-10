#!/bin/bash
# Deploy PostgreSQL to separate EC2 instance

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yml"

# Detect docker-compose command
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Error: docker-compose not found!${NC}"
    echo -e "${YELLOW}Please install Docker Compose first:${NC}"
    echo "  sudo bash setup.sh"
    exit 1
fi

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: $ENV_FILE not found!${NC}"
    echo -e "${YELLOW}Please copy env.example to $ENV_FILE and configure it.${NC}"
    exit 1
fi

echo -e "${BLUE}Deploying PostgreSQL to EC2 instance...${NC}"

# Create backups directory if it doesn't exist
mkdir -p backups

# Start PostgreSQL
echo -e "${BLUE}Starting PostgreSQL container...${NC}"
$DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# Wait for PostgreSQL to be ready
echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"
sleep 5

# Check service health
echo -e "${BLUE}Checking service status...${NC}"
$DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

# Test connection
echo -e "${BLUE}Testing PostgreSQL connection...${NC}"
if $DOCKER_COMPOSE -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T postgres pg_isready -U ${POSTGRES_USER:-postgres} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL is ready!${NC}"
else
    echo -e "${YELLOW}PostgreSQL is starting up, please wait...${NC}"
fi

# Get and display private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "N/A")

echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Connection Information:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}PostgreSQL EC2 Private IP:${NC} $PRIVATE_IP"
echo -e "  ${YELLOW}PostgreSQL EC2 Public IP:${NC}  $PUBLIC_IP (for SSH only)"
echo -e "  ${YELLOW}Database Port:${NC}             5432"
echo -e "  ${YELLOW}Database Name:${NC}             ${POSTGRES_DB:-mock_fitband_db}"
echo -e "  ${YELLOW}Database User:${NC}             ${POSTGRES_USER:-postgres}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT - App EC2 Configuration:${NC}"
echo -e "  Update your App EC2's DATABASE_URL:"
echo -e "  ${GREEN}DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:<PASSWORD>@$PRIVATE_IP:5432/${POSTGRES_DB:-mock_fitband_db}?schema=public${NC}"
echo ""
echo -e "${YELLOW}⚠️  SECURITY - AWS Security Group Configuration:${NC}"
echo -e "  Ensure AWS Security Group allows port 5432 ONLY from your App EC2's private IP"
echo -e "  See README.md for detailed Security Group configuration steps"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo "  View logs:        $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo "  View postgres logs: $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE logs -f postgres"
echo "  Stop service:     $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "  Restart service:  $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE restart"
echo "  View status:      $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE ps"
echo "  Connect to DB:    $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE exec postgres psql -U \${POSTGRES_USER:-postgres} -d \${POSTGRES_DB:-mock_fitband_db}"
echo "  Create backup:    ./backup.sh"
echo ""

