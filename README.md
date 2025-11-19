# PostgreSQL VM Deployment

This folder contains configuration and scripts to deploy PostgreSQL on a separate Azure VM.

## Architecture

- **PostgreSQL VM**: Dedicated VM running only PostgreSQL
- **App VM**: Separate VM running the application (connects to PostgreSQL VM)

## Prerequisites

- Azure VM (Ubuntu 20.04+ or similar Linux distribution)
- SSH access to the VM
- Minimum 2 vCPUs, 4GB RAM, 20GB disk (8GB RAM recommended for production)

## Quick Start

### 1. Create Azure VM for PostgreSQL

```bash
# Using Azure CLI
az vm create \
  --resource-group mock-fitband-rg \
  --name mock-fitband-postgres-vm \
  --image Ubuntu2204 \
  --size Standard_B2ms \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Get VM IP
az vm show -d -g mock-fitband-rg -n mock-fitband-postgres-vm --query publicIps -o tsv
```

### 2. Copy Files to VM

```bash
# From your local machine
scp -r deployment/postgres-vm/* azureuser@<POSTGRES_VM_IP>:/opt/postgres-vm/
```

Or clone the repo on the VM:
```bash
# On the VM
sudo mkdir -p /opt/postgres-vm
sudo chown $USER:$USER /opt/postgres-vm
cd /opt/postgres-vm
# Copy files from your repo
```

### 3. Initial Setup

```bash
cd /opt/postgres-vm
chmod +x *.sh
sudo bash setup.sh
```

### 4. Configure Environment

```bash
cp env.example .env
nano .env
```

**IMPORTANT**: Update these values:
- `POSTGRES_PASSWORD`: Generate a strong password (use `openssl rand -base64 32`)

### 5. Deploy PostgreSQL

```bash
./deploy.sh
```

### 6. Get PostgreSQL VM Private IP

```bash
# On PostgreSQL VM
hostname -I | awk '{print $1}'
```

Save this IP - you'll need it for the app VM configuration.

## Network Security Configuration

### Azure NSG Rules

Configure Network Security Group (NSG) to allow PostgreSQL access **only from your app VM**:

1. Go to Azure Portal → Network Security Groups
2. Find the NSG for your PostgreSQL VM
3. Add Inbound Rule:
   - **Name**: Allow-PostgreSQL-From-App-VM
   - **Priority**: 1000
   - **Source**: IP Addresses
   - **Source IP**: Your App VM's private IP (or subnet)
   - **Protocol**: TCP
   - **Port**: 5432
   - **Action**: Allow

**Security Best Practice**: Only allow port 5432 from your app VM's private IP address, not from the internet.

## App VM Configuration

On your **app VM**, update the `DATABASE_URL` in `.env.prod`:

```env
# Replace <POSTGRES_VM_PRIVATE_IP> with the actual private IP
DATABASE_URL=postgresql://postgres:your-password@<POSTGRES_VM_PRIVATE_IP>:5432/mock_fitband_db?schema=public
```

Also update `docker-compose.prod.yml` on the app VM to remove the `db` service and update the app service to connect to the remote database.

## Backup Configuration

### Manual Backup

```bash
./backup.sh
```

### Automated Backups (Cron)

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /opt/postgres-vm && ./backup.sh >> /var/log/postgres-backup.log 2>&1
```

## Restore from Backup

```bash
# Extract backup
gunzip backups/backup_YYYYMMDD_HHMMSS.sql.gz

# Restore
docker-compose -f docker-compose.yml --env-file .env exec -T postgres \
  psql -U postgres -d mock_fitband_db < backups/backup_YYYYMMDD_HHMMSS.sql
```

## Common Operations

### View Logs

```bash
docker-compose -f docker-compose.yml --env-file .env logs -f
```

### Connect to Database

```bash
docker-compose -f docker-compose.yml --env-file .env exec postgres \
  psql -U postgres -d mock_fitband_db
```

### Restart PostgreSQL

```bash
docker-compose -f docker-compose.yml --env-file .env restart postgres
```

### Stop PostgreSQL

```bash
docker-compose -f docker-compose.yml --env-file .env down
```

### Check Status

```bash
docker-compose -f docker-compose.yml --env-file .env ps
```

## Auto-Start on Boot

Create a systemd service:

```bash
sudo nano /etc/systemd/system/postgres-vm.service
```

Add:

```ini
[Unit]
Description=PostgreSQL VM Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/postgres-vm
ExecStart=/usr/bin/docker compose -f docker-compose.yml --env-file .env up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml --env-file .env down
TimeoutStartSec=0
User=azureuser
Group=azureuser

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable postgres-vm
sudo systemctl start postgres-vm
```

## Troubleshooting

### Can't Connect from App VM

1. Check NSG rules allow port 5432 from app VM
2. Verify PostgreSQL is running: `docker-compose ps`
3. Test connection from app VM: `telnet <POSTGRES_VM_IP> 5432`
4. Check PostgreSQL logs: `docker-compose logs postgres`

### Connection Refused

- Verify PostgreSQL container is running
- Check firewall rules on PostgreSQL VM
- Verify Azure NSG allows the connection
- Check PostgreSQL is listening on the correct interface

### Out of Disk Space

```bash
# Clean up old backups
find backups -name "*.sql.gz" -mtime +7 -delete

# Clean up Docker
docker system prune -a --volumes
```

## Security Checklist

- [ ] Changed default `POSTGRES_PASSWORD` to strong password
- [ ] Azure NSG configured to allow port 5432 only from app VM
- [ ] Firewall on VM configured correctly
- [ ] `.env` file permissions: `chmod 600 .env`
- [ ] Regular backups configured
- [ ] Backups stored securely (consider Azure Blob Storage)
- [ ] SSL/TLS enabled for PostgreSQL connections (optional but recommended)

## Monitoring

### Check Resource Usage

```bash
docker stats
htop
```

### Check Database Size

```bash
docker-compose -f docker-compose.yml --env-file .env exec postgres \
  psql -U postgres -d mock_fitband_db -c "SELECT pg_size_pretty(pg_database_size('mock_fitband_db'));"
```

### Check Active Connections

```bash
docker-compose -f docker-compose.yml --env-file .env exec postgres \
  psql -U postgres -d mock_fitband_db -c "SELECT count(*) FROM pg_stat_activity;"
```

