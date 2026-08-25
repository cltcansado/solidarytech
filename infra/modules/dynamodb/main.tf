# PAY_PER_REQUEST (on-demand): decisão de FinOps deliberada — carga do volunteer-service é
# imprevisível (picos de acesso citados no enunciado) e não temos histórico de tráfego para
# dimensionar capacidade provisionada com segurança. Reavaliar para provisioned+autoscaling
# só depois de observar padrão real de uso por >=2 semanas (ver docs/FINOPS-FORECAST.md).
resource "aws_dynamodb_table" "volunteers" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = true # RPO ~ contínuo para os dados de voluntários (ver docs/PCN-DR.md)
  }

  tags = var.tags
}
