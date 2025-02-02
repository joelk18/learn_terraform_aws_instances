output "s3_data_bucket" {
  value = aws_s3_bucket.data_bucket.bucket
}

output "rds_endpoint" {
  value = aws_db_instance.rds_instance.endpoint
}
