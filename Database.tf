provider "aws" {
  region = "ap-northeast-3"
}

// VPC
resource "aws_vpc" "osaka" {
  cidr_block           = "10.79.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.osaka
  tags = {
    Name = "Osaka VPC"
  }
}

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "aurora-postgres-cluster"
  engine                  = "aurora-postgresql"
  database_name           = "TeleMedicinedb"
  master_username         = "ResultsSpeakLouderMasterUser"
  master_password         = "5uperDuperP-55w0rd"
  backup_retention_period = 7
  preferred_backup_window = "05:00-07:00"
  skip_final_snapshot     = true

  availability_zones = ["ap-northeast-3a"]
  provider             = aws.osaka

  tags = {
    Name        = "aurora-postgres-cluster"
    Environment = "Production"
  }
}

resource "aws_rds_cluster_instance" "aurora_cluster_instances" {
  count              = 2
  identifier         = "aurora-postgres-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.aurora_cluster.engine
  provider           = aws.osaka

  tags = {
    Name        = "aurora-postgres-instance-${count.index + 1}"
    Environment = "Production"
  }
}

resource "aws_security_group" "aurora_sg" {
  name        = "aurora-sg"
  description = "Allow Aurora PostgreSQL traffic"
  vpc_id      = aws_vpc.osaka.id 
  provider    = aws.osaka

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this to trusted IPs or CIDR blocks in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



resource "aws_rds_cluster_parameter_group" "aurora_parameter_group" {
  name     = "aurora-cluster-parameter-group"
  family   = "aurora-postgresql13"
  provider = aws.osaka

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}


output "aurora_cluster_endpoint" {
  value       = aws_rds_cluster.aurora_cluster.endpoint
  description = "The endpoint for the Aurora cluster (read/write operations)."
}

output "aurora_reader_endpoint" {
  value       = aws_rds_cluster.aurora_cluster.reader_endpoint
  description = "The endpoint for the Aurora cluster (read-only operations)."
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow EC2 instances to communicate with Aurora"
  vpc_id      = aws_vpc.osaka.id # Replace with your VPC ID
  provider    = aws.osaka
}

resource "aws_security_group_rule" "allow_ec2_to_aurora" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora_sg.id
  source_security_group_id = aws_security_group.ec2_sg.id
  provider                 = aws.osaka
}