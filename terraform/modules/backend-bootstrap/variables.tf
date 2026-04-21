# backend-bootstrap/variables.tf

variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Nome do bucket S3 para armazenar os estados (deve ser globalmente único)"
  type        = string
  default     = "tcc-tfstate-atlantis"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para state locking"
  type        = string
  default     = "terraform-locks"
}