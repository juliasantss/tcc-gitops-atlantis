# backend-bootstrap/outputs.tf

output "state_bucket_name" {
  description = "Nome do bucket S3 criado"
  value       = aws_s3_bucket.tfstate.id
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB criada"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  description = "Região AWS utilizada"
  value       = var.aws_region
}