# backend-bootstrap/main.tf
# Provisiona o bucket S3 e a tabela DynamoDB para o backend remoto do Terraform.
# Executar localmente uma única vez antes de usar os ambientes.

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

# Bucket S3 para armazenar os estados do Terraform
resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  # Impedir destruição acidental
  lifecycle {
    prevent_destroy = false
  }
}

# Versionamento obrigatório para histórico de estados
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia no lado do servidor
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueio de acesso público (segurança)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tabela DynamoDB para state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Proteção contra exclusão acidental
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name = "terraform-state-locks"
  }
}