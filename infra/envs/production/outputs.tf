output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "sqs_dlq_url" {
  value = module.sqs.dlq_url
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "redis_endpoint" {
  value = module.redis.endpoint
}

output "velero_bucket_name" {
  value = module.velero_backend.bucket_name
}

output "configure_kubectl" {
  description = "Comando para configurar o kubeconfig local (única vez, por operador humano — não é deploy, é acesso de leitura/debug)"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
