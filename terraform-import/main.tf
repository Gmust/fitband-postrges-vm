# PostgreSQL EC2 Infrastructure
# This Terraform configuration manages the PostgreSQL EC2 instance and related resources

provider "aws" {
  region = var.aws_region
}

# Data sources for existing resources
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for PostgreSQL EC2
resource "aws_security_group" "postgres_vm" {
  name        = "postgres-vm-sg"
  description = "Security group for PostgreSQL VM"
  vpc_id      = data.aws_vpc.default.id

  # SSH access from anywhere (for management)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL access - restricted to specific IPs
  ingress {
    description = "PostgreSQL from App EC2"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [
      "172.31.79.89/32",    # App EC2 private IP
      "172.31.76.168/32",   # New EC2 instance
    ]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-vm-sg"
  }
}

# Security Group Rules for additional IPs (optional, managed separately)
resource "aws_security_group_rule" "postgres_local_ips" {
  for_each = toset(var.allowed_postgres_ips)

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["${each.value}/32"]
  security_group_id = aws_security_group.postgres_vm.id
  description       = "PostgreSQL access from ${each.value}"
}

# Key Pair (if you want to manage it with Terraform)
# Uncomment if you want Terraform to manage the key pair
# resource "aws_key_pair" "postgres_vm" {
#   key_name   = var.key_pair_name
#   public_key = file(var.public_key_path)
# }

# EC2 Instance for PostgreSQL
resource "aws_instance" "postgres_vm" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.postgres_vm.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  # Root volume
  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
    encrypted   = true
  }

  # User data script for initial setup
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y docker.io docker-compose
    systemctl enable docker
    systemctl start docker
    mkdir -p /opt/postgres-vm
  EOF

  tags = {
    Name = var.instance_name
  }
}

# Elastic IP (optional - for static public IP)
resource "aws_eip" "postgres_vm" {
  count = var.assign_elastic_ip ? 1 : 0

  instance = aws_instance.postgres_vm.id
  domain   = "vpc"

  tags = {
    Name = "${var.instance_name}-eip"
  }
}

# Outputs
output "postgres_instance_id" {
  description = "PostgreSQL EC2 Instance ID"
  value       = aws_instance.postgres_vm.id
}

output "postgres_private_ip" {
  description = "PostgreSQL EC2 Private IP"
  value       = aws_instance.postgres_vm.private_ip
}

output "postgres_public_ip" {
  description = "PostgreSQL EC2 Public IP"
  value       = var.assign_elastic_ip ? aws_eip.postgres_vm[0].public_ip : aws_instance.postgres_vm.public_ip
}

output "security_group_id" {
  description = "PostgreSQL Security Group ID"
  value       = aws_security_group.postgres_vm.id
}

output "connection_string" {
  description = "PostgreSQL connection string template"
  value       = "postgresql://postgres:PASSWORD@${aws_instance.postgres_vm.private_ip}:5432/mock_fitband_db?schema=public"
  sensitive   = false
}

