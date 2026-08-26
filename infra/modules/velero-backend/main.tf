# Bucket S3 de destino dos backups do Velero (Opção A de DR - ver docs/PCN-DR.md).
# Provisionado por padrão em região diferente do cluster (ver var region no provider,
# configurado no root module com alias `dr`), cumprindo o requisito de
# "backup cross-region para um bucket externo".
#
# Credenciais do Velero: sem IRSA disponível (restrição AWS Academy), o pod do Velero herda
# as permissões da LabRole via role de instância do nó (IMDS), igual ao healer-service e aos
# demais serviços que falam com SQS/DynamoDB. 
resource "aws_s3_bucket" "velero" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_expiration_days
    }
  }
}
