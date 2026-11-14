terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  required_version = ">= 1.5"

  backend "s3" {
    bucket = "oficina-marimb0ndo-tfstate-528568030535"
    key    = "infra-k8s/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# AMI Amazon Linux 2023 mais recente
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group para o k3s
resource "aws_security_group" "k3s_sg" {
  name        = "oficina-k3s-sg"
  description = "Security group para o cluster k3s"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # API do k3s apenas dentro da VPC (deploys usam SSH + kubectl no próprio nó)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
    description = "k3s API server (somente VPC)"
  }

  # NodePorts (30080/30081) NÃO são expostos: o acesso externo é só pelo API Gateway -> Ingress (80),
  # e os serviços exigem o header x-origin-verify injetado pelo Gateway.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "oficina-k3s-sg"
    Environment = var.environment
    Project     = "oficina-marimb0ndo"
  }
}

# Key pair para SSH
resource "aws_key_pair" "oficina" {
  key_name   = "oficina-k3s-key"
  public_key = file("${path.module}/oficina-k3s-key.pub")
}

# EC2 t3.medium para k3s (t2.micro é insuficiente para k3s + app)
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  key_name               = aws_key_pair.oficina.key_name

  # Learner Lab: perfil pré-existente (não é possível criar roles). Dá aos pods
  # credenciais temporárias via IMDS para acessar o DynamoDB do billing-service.
  iam_instance_profile = var.instance_profile_name

  # hop limit 2: o IMDSv2 precisa responder aos containers (1 salto extra pela rede do k3s)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30 # AMIs AL2023 recentes exigem >= 30GB
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host              = var.db_host
    db_password          = var.db_password
    jwt_secret           = var.jwt_secret
    internal_api_key     = var.internal_api_key
    origin_verify_secret = random_password.origin_verify.result
  }))

  tags = {
    Name        = "oficina-k3s-node"
    Environment = var.environment
    Project     = "oficina-marimb0ndo"
  }
}

# IP elástico para a EC2
resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = {
    Name    = "oficina-k3s-eip"
    Project = "oficina-marimb0ndo"
  }
}
