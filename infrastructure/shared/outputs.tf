output "vpc_id" {
  description = "Shared non-prod VPC ID"
  value       = aws_vpc.shared.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (AZ a, b)"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (AZ a, b)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
