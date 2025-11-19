# App VM Setup with Remote PostgreSQL

This guide explains how to configure your **App VM** to connect to the remote PostgreSQL VM.

## Prerequisites

- PostgreSQL VM is deployed and running
- You have the PostgreSQL VM's private IP address
- You have the PostgreSQL password from the PostgreSQL VM's `.env` file

## Step 1: Update App VM Environment

On your **App VM**, update `.env.prod`:

```bash
cd /opt/mock-fitband-api/fitband-api
nano .env.prod
```

Update the `DATABASE_URL` to point to your PostgreSQL VM:

```env
# Replace <POSTGRES_VM_PRIVATE_IP> with the actual private IP from PostgreSQL VM
# Replace <POSTGRES_PASSWORD> with the password from PostgreSQL VM's .env
DATABASE_URL=postgresql://postgres:<POSTGRES_PASSWORD>@<POSTGRES_VM_PRIVATE_IP>:5432/mock_fitband_db?schema=public

# Keep other settings
POSTGRES_DB=mock_fitband_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<POSTGRES_PASSWORD>  # Same as in DATABASE_URL
NODE_ENV=production
PORT=8080
APP_PORT=8080
RUN_MIGRATIONS=true
CORS_ORIGIN=https://your-domain.com
```

## Step 2: Update Docker Compose File

Option A: Use the provided remote DB compose file:

```bash
# Copy the remote DB compose file
cp deployment/postgres-vm/docker-compose.app-remote-db.yml docker-compose.prod.yml
```

Option B: Manually update your existing `docker-compose.prod.yml`:

Remove the `db` service entirely and update the `app` service:

```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: mock-fitband-api:prod
    container_name: mock-fitband-api-app
    ports:
      - "${APP_PORT:-8080}:8080"
    environment:
      - NODE_ENV=production
      - PORT=8080
      - DATABASE_URL=${DATABASE_URL}
      - RUN_MIGRATIONS=${RUN_MIGRATIONS:-true}
      - CORS_ORIGIN=${CORS_ORIGIN:-*}
      - LOG_LEVEL=${LOG_LEVEL:-info}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:8080/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    # No depends_on - PostgreSQL is on remote VM
```

## Step 3: Test Connection

Before deploying, test the connection:

```bash
# From App VM, test if you can reach PostgreSQL VM
telnet <POSTGRES_VM_PRIVATE_IP> 5432

# Or use nc (netcat)
nc -zv <POSTGRES_VM_PRIVATE_IP> 5432
```

If connection fails, check:
1. Azure NSG rules allow port 5432 from app VM to PostgreSQL VM
2. PostgreSQL container is running on PostgreSQL VM
3. Firewall on PostgreSQL VM allows the connection

## Step 4: Deploy App

```bash
# Rebuild and restart with new configuration
sudo docker-compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

## Step 5: Verify Deployment

```bash
# Check container status
sudo docker-compose -f docker-compose.prod.yml --env-file .env.prod ps

# Check logs
sudo docker-compose -f docker-compose.prod.yml --env-file .env.prod logs -f app

# Test API
curl http://localhost:8080/health
```

## Troubleshooting

### Connection Timeout

**Problem**: App can't connect to PostgreSQL VM

**Solutions**:
1. Verify PostgreSQL VM private IP is correct
2. Check Azure NSG allows port 5432 from app VM
3. Verify PostgreSQL container is running: `docker-compose ps` on PostgreSQL VM
4. Test network connectivity: `telnet <POSTGRES_VM_IP> 5432` from app VM

### Authentication Failed

**Problem**: Wrong password or user

**Solutions**:
1. Verify `POSTGRES_PASSWORD` in `.env.prod` matches PostgreSQL VM's `.env`
2. Verify `POSTGRES_USER` is correct (default: `postgres`)
3. Check PostgreSQL logs on PostgreSQL VM for authentication errors

### Database Not Found

**Problem**: Database doesn't exist

**Solutions**:
1. Verify `POSTGRES_DB` matches the database name on PostgreSQL VM
2. Run migrations manually if needed
3. Check if database was created on PostgreSQL VM

## Network Security

### Azure NSG Configuration

Ensure your App VM's NSG allows outbound connections to PostgreSQL VM:
- **Outbound Rule**: Allow TCP port 5432 to PostgreSQL VM's private IP

Ensure PostgreSQL VM's NSG allows inbound connections from App VM:
- **Inbound Rule**: Allow TCP port 5432 from App VM's private IP

### Best Practices

1. Use private IPs for database connections (not public IPs)
2. Restrict NSG rules to specific source IPs (app VM's private IP)
3. Never expose PostgreSQL port (5432) to the internet
4. Consider using Azure Private Link for enhanced security
5. Use strong passwords and consider SSL/TLS for database connections

## Migration from Single VM Setup

If you're migrating from a single VM setup:

1. **Backup existing database**:
   ```bash
   # On old VM
   docker-compose -f docker-compose.prod.yml --env-file .env.prod exec db \
     pg_dump -U postgres mock_fitband_db > backup.sql
   ```

2. **Restore to new PostgreSQL VM**:
   ```bash
   # On PostgreSQL VM
   scp user@old-vm:/path/to/backup.sql .
   docker-compose -f docker-compose.yml --env-file .env exec -T postgres \
     psql -U postgres -d mock_fitband_db < backup.sql
   ```

3. **Update App VM** as described above

4. **Test thoroughly** before decommissioning old VM

