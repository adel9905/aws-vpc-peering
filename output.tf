# Output Bastion host's public IP
output "bastion_public_ip" {
  value = aws_instance.bastionhost.public_ip
}
# Output Bastion host's private IP
output "bastion_private_ip" {
  value = aws_instance.bastionhost.private_ip
}

output "rds_endpoint" {
  value = aws_db_instance.DB.endpoint
}
