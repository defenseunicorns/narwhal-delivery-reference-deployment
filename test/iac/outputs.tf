output "region" {
  value = var.region
}

output "server_id" {
  value = module.server.instance_id
}

output "vpc_cidr" {
  value = var.vpc_cidr
}

output "s3_bucket_automation" {
  value = aws_s3_bucket.tf-copy-file-s3.name
}