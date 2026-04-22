# outputs.tf

output "vpc_id" {
  value = module.networking.vpc_id
}

output "asg_name" {
  value = module.compute.asg_name
}

output "app_security_group_id" {
  value = module.compute.security_group_id
}