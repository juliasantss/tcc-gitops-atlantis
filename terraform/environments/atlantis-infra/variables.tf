# variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# variable "acm_certificate_arn" {
#   description = "ARN of ACM certificate for HTTPS (leave empty to use HTTP only)"
#   type        = string
#   default     = ""
# }

variable "github_user" {
  description = "GitHub username or organization"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token (classic)"
  type        = string
  sensitive   = true
}

variable "github_webhook_secret" {
  description = "Secret for GitHub webhook"
  type        = string
  sensitive   = true
  default     = ""
}