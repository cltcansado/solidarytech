output "bucket_name" {
  value = aws_s3_bucket.velero.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.velero.arn
}
