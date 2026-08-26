# Bootstrap do backend remoto de state (S3 + DynamoDB lock).
#
# Este módulo é aplicado UMA ÚNICA VEZ, com state local: não dá para guardar o state do
# backend dentro do próprio backend que ele cria. Depois de aplicado,
# `infra/envs/production` referencia o bucket/tabela criados aqui via `backend "s3"`.
#
# Uso:
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var="bucket_suffix=<algo-unico-ex-RM ou conta>"

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_suffix" {
  description = "Sufixo único para o bucket de state (ex: conta AWS Academy ou RM do grupo)"
  type        = string
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "solidarytech-tfstate-${var.bucket_suffix}"

  tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
    Purpose     = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3 (não KMS custom - indisponível na AWS Academy)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "solidarytech-tfstate-lock-${var.bucket_suffix}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
    Purpose     = "terraform-state-lock"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}
