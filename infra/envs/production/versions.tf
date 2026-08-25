terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  # Preencha com o bucket/tabela criados em infra/bootstrap (terraform output lá).
  # Mantido comentado no repo — cada ambiente informa via `-backend-config` no CI
  # (ver .github/workflows/terraform.yml) para não hardcodar nome de bucket específico
  # de uma conta AWS Academy no código versionado.
  backend "s3" {
    # bucket         = "solidarytech-tfstate-<sufixo>"
    # key            = "production/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "solidarytech-tfstate-lock-<sufixo>"
    # encrypt        = true
  }
}

# Provider AWS principal (região do cluster/produção).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = module.tags.tags
  }
}

# Provider AWS secundário — usado apenas pelo bucket de backup do Velero (Opção A de DR,
# cross-region por definição). Ver docs/PCN-DR.md.
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = module.tags.tags
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

# repository_config_path/repository_cache isolados neste diretório: evita que o provider
# reutilize o cache global de Helm da máquina (~/.cache/helm ou %APPDATA%\helm), que pode ter
# entradas de outros projetos (ex: repos de Fases anteriores) corrompidas/inacessíveis.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
  repository_config_path = "${path.module}/.helm/repositories.yaml"
  repository_cache       = "${path.module}/.helm/cache"
}

# Usado só para o Application (CRD do ArgoCD) do app-of-apps — ver comentário em
# infra/modules/argocd/main.tf sobre por que kubectl_manifest e não kubernetes_manifest.
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}
