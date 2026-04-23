# main.tf - Ambiente Dev (aplicação de exemplo)

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "../../modules/networking"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = "dev"
}

module "compute" {
  source = "../../modules/compute"

  environment        = "dev"
  instance_type      = "t3.micro"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.public_subnet_ids
  user_data          = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>Hello from GitOps + Atlantis! (dev)</h1>" > /usr/share/nginx/html/index.html
  EOF
}