# outputs.tf

output "alb_dns_name" {
  description = "DNS name of the ALB (use this for GitHub webhook URL)"
  value       = aws_lb.atlantis.dns_name
}

output "atlantis_url" {
  description = "Full URL for Atlantis webhook endpoint"
  value       = "http://${aws_lb.atlantis.dns_name}/events"
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}