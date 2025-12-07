output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = module.rds.db_instance_arn
}

output "db_instance_address" {
  description = "The connection endpoint (hostname) of the RDS instance"
  value       = module.rds.db_instance_address
}

output "db_instance_endpoint" {
  description = "The connection endpoint (hostname:port) of the RDS instance"
  value       = module.rds.db_instance_endpoint
}

output "db_username" {
  description = "The master username for the database"
  value       = module.rds.db_instance_username
}

output "db_instance_port" {
  description = "The port of the RDS instance"
  value       = module.rds.db_instance_port
}