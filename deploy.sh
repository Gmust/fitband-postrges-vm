#!/bin/bash
# Deploy PostgreSQL to separate VM

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

echo -e "${BLUE}Deploying PostgreSQL to VM...${NC}"

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

echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  View logs:        $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo "  View postgres logs: $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE logs -f postgres"
echo "  Stop service:     $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "  Restart service:  $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE restart"
echo "  View status:      $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE ps"
echo "  Connect to DB:    $DOCKER_COMPOSE -f $COMPOSE_FILE --env-file $ENV_FILE exec postgres psql -U \${POSTGRES_USER:-postgres} -d \${POSTGRES_DB:-mock_fitband_db}"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  - Get this VM's private IP: hostname -I | awk '{print \$1}'"
echo "  - Update your app VM's DATABASE_URL to use this IP"
echo "  - Ensure Azure NSG allows port 5432 from your app VM only"

