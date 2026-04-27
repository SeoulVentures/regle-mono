# =============================================================================
# regle-makeshop production 인프라
# =============================================================================
# 환경: production (단일 EC2 + RDS Postgres). dev (regle-mcp-server) 는 별도 state.
# 생성: 2026-04-27. 초기 자원은 AWS CLI 로 만든 후 본 코드로 import.
# 보관 단일 진실 원천: s3://sv-env/regle/mcp-makeshop/admin-info.txt
# =============================================================================

# Latest Ubuntu 24.04 ARM64 — instance lifecycle.ignore_changes 로 ami 미반영
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "regle-makeshop-prod-ec2"
  description = "Production EC2 (mcp-makeshop) 80/443/22"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (Lets Encrypt + 443 redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "regle-makeshop-prod-ec2"
    Project     = "regle-makeshop"
    Environment = "production"
  }
}

resource "aws_security_group" "rds" {
  name        = "regle-makeshop-prod-rds"
  description = "Production RDS Postgres (5432 from EC2 only)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "regle-makeshop-prod-rds"
    Project     = "regle-makeshop"
    Environment = "production"
  }
}

# -----------------------------------------------------------------------------
# EC2 (web + mcp Rust co-located)
# -----------------------------------------------------------------------------

resource "aws_instance" "ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t4g.small"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = var.ec2_subnet_id

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = false # 초기 import 시 false. 후일 snapshot+restore 로 전환 가능
    delete_on_termination = true
  }

  tags = {
    Name        = "regle-makeshop-prod"
    Project     = "regle-makeshop"
    Env         = "production"
    Environment = "production"
  }

  # OS / package / .env / systemd unit 은 deploy-ec2.yml 가 관리.
  # AMI 갱신은 별도 spec 으로 (lifecycle 재기동 위험).
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "ec2" {
  instance = aws_instance.ec2.id
  domain   = "vpc"

  tags = {
    Name        = "regle-makeshop-prod-eip"
    Project     = "regle-makeshop"
    Environment = "production"
  }
}

# -----------------------------------------------------------------------------
# RDS Postgres
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "rds" {
  name        = "regle-makeshop-prod"
  description = "regle-makeshop production"
  subnet_ids  = var.rds_subnet_ids

  tags = {
    Name        = "regle-makeshop-prod"
    Project     = "regle-makeshop"
    Environment = "production"
  }
}

resource "aws_db_instance" "rds" {
  identifier     = "regle-makeshop-prod"
  engine         = "postgres"
  engine_version = "16.10"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "mcp_makeshop"
  username = "postgres"
  password = var.rds_master_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  apply_immediately = false

  tags = {
    Name        = "regle-makeshop-prod"
    Project     = "regle-makeshop"
    Environment = "production"
  }

  lifecycle {
    # password 회전은 평문이라 plan diff 가 자주 발생. 회전 시점에만 변수 갱신.
    ignore_changes = [
      engine_version, # minor 자동 업그레이드
    ]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ec2_id" {
  value = aws_instance.ec2.id
}

output "ec2_public_ip" {
  value = aws_eip.ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.rds.endpoint
}

output "rds_address" {
  value = aws_db_instance.rds.address
}
