# backend.tf
terraform {
  backend "s3" {
    bucket         = "tcc-tfstate-atlantis" # <-- SUBSTITUA PELO NOME REAL DO SEU BUCKET
    key            = "atlantis-infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}