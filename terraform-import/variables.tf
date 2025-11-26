variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"  # Paris (France Central)
}

variable "instance_name" {
  description = "Name tag for the PostgreSQL EC2 instance"
  type        = string
  default     = "mock-fitband-postgres-vm"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 22.04 LTS"
  type        = string
  # Default for eu-west-3 (Paris), update for other regions
  default = ""
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

variable "volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 30
}

variable "assign_elastic_ip" {
  description = "Whether to assign an Elastic IP to the instance"
  type        = bool
  default     = true
}

variable "allowed_postgres_ips" {
  description = "List of additional IP addresses allowed to connect to PostgreSQL (CIDR format without /32)"
  type        = list(string)
  default     = []
}

variable "public_key_path" {
  description = "Path to public key file (if managing key pair with Terraform)"
  type        = string
  default     = ""
}

