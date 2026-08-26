module "tags" {
  source = "../../modules/tags"

  project     = "SolidaryTech"
  environment = "Production"
  cost_center = "NGO-Core"
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "solidarytech"
  cluster_name = var.cluster_name
  tags         = module.tags.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids    = module.vpc.private_subnet_ids
  cluster_role_arn   = var.lab_role_arn
  node_role_arn      = var.lab_role_arn
  tags               = module.tags.tags
}

module "ecr" {
  source = "../../modules/ecr"
  tags   = module.tags.tags
}

module "sqs" {
  source = "../../modules/sqs"
  tags   = module.tags.tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"
  tags   = module.tags.tags
}

module "rds" {
  source = "../../modules/rds"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  master_username            = var.rds_master_username
  master_password            = var.rds_master_password
  tags                       = module.tags.tags
}

module "redis" {
  source = "../../modules/redis"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  tags                       = module.tags.tags
}

module "velero_backend" {
  source = "../../modules/velero-backend"
  providers = {
    aws = aws.dr
  }

  bucket_name = "solidarytech-velero-backups-${var.velero_bucket_suffix}"
  tags        = module.tags.tags
}

# StorageClass padrão do cluster, backeada pelo EBS CSI driver (module.eks.aws_eks_addon.
# ebs_csi_driver) — sem isso, todo PersistentVolumeClaim (Prometheus, Grafana, Loki, Velero)
# fica "Pending" para sempre. A `gp2` que o EKS deixa como leftover usa o provisioner in-tree
# antigo (`kubernetes.io/aws-ebs`), não o CSI driver — substituída aqui por uma default real.
resource "kubernetes_storage_class_v1" "gp3_default" {
  count = var.enable_argocd_bootstrap ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}

# Namespace da aplicação + Secrets com os dados de conexão (RDS/SQS/DynamoDB/Redis) gerados
# pelo próprio Terraform. Decisão de arquitetura: segredos são responsabilidade do Terraform
# (que já sabe endpoint/senha porque acabou de provisionar o recurso), workloads são
# responsabilidade do GitOps/ArgoCD — os Deployments em gitops/apps/*/ só referenciam o NOME
# do Secret via secretKeyRef, nunca o valor. Isso evita commitar qualquer credencial no Git,
# sem depender de Vault/Sealed Secrets/External Secrets Operator (fora de escopo do hackathon).
resource "kubernetes_namespace" "solidarytech" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name = "solidarytech"
  }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "ngo_service_db" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name      = "ngo-service-db"
    namespace = kubernetes_namespace.solidarytech[0].metadata[0].name
  }
  data = {
    DATABASE_URL = "postgres://${var.rds_master_username}:${var.rds_master_password}@${module.rds.address}:${module.rds.port}/ngo_db"
  }
}

resource "kubernetes_secret" "donation_service_db" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name      = "donation-service-db"
    namespace = kubernetes_namespace.solidarytech[0].metadata[0].name
  }
  data = {
    DATABASE_URL = "postgres://${var.rds_master_username}:${var.rds_master_password}@${module.rds.address}:${module.rds.port}/donation_db"
    AWS_SQS_URL  = module.sqs.queue_url
  }
}

resource "kubernetes_secret" "rds_admin" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name      = "rds-admin"
    namespace = kubernetes_namespace.solidarytech[0].metadata[0].name
  }
  data = {
    # aponta para o banco `ngo_db` (o único criado automaticamente pelo RDS) — usado só
    # pelo Job de PreSync do donation-service para dar `CREATE DATABASE donation_db`.
    ADMIN_DATABASE_URL = "postgres://${var.rds_master_username}:${var.rds_master_password}@${module.rds.address}:${module.rds.port}/ngo_db"
  }
}

resource "kubernetes_secret" "volunteer_service_env" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name      = "volunteer-service-env"
    namespace = kubernetes_namespace.solidarytech[0].metadata[0].name
  }
  data = {
    AWS_DYNAMODB_TABLE = module.dynamodb.table_name
  }
}

resource "kubernetes_namespace" "observability" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name = "observability"
  }
  depends_on = [module.eks]
}

# Credenciais do APM (Datadog) consumidas pelo OTel Collector (repo solidarytech-gitops,
# observability/otel-collector). Opcionais/vazias por padrão: o cluster sobe e os outros
# exporters (debug/prometheus) continuam funcionando mesmo sem conta de APM ainda criada —
# preencha via TF_VAR_* quando tiver a conta.
resource "kubernetes_secret" "apm_credentials" {
  count = var.enable_argocd_bootstrap ? 1 : 0
  metadata {
    name      = "apm-credentials"
    namespace = kubernetes_namespace.observability[0].metadata[0].name
  }
  data = {
    DD_API_KEY = var.datadog_api_key
    DD_SITE    = var.datadog_site
  }
}

# Bootstrap do GitOps: instala o ArgoCD e aponta para o app-of-apps do repo gitops.
# A partir daqui, TUDO que roda no cluster (observabilidade, os 3 serviços, healer-service,
# Velero) é sincronizado pelo próprio ArgoCD lendo o repositório Git — não há mais nenhum
# outro `helm install`/`kubectl apply` de infraestrutura de aplicação feito via Terraform.
module "argocd" {
  count  = var.enable_argocd_bootstrap ? 1 : 0
  source = "../../modules/argocd"

  gitops_repo_url  = var.gitops_repo_url
  gitops_root_path = "argocd/apps"
  target_revision  = var.gitops_target_revision
  git_repo_token   = var.git_repo_token

  depends_on = [module.eks]
}
