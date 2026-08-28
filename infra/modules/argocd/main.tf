# Instala o ArgoCD via Helm (Terraform) e aplica o "app-of-apps" raiz via `kubectl_manifest`
# (provider gavinbunney/kubectl, não hashicorp/kubernetes) - ou seja, o ÚNICO objeto do
# cluster que nasce fora do fluxo 100% GitOps é este bootstrap inicial, e mesmo assim ele é
# aplicado pelo Terraform, nunca por um `kubectl apply` manual de humano. A partir daqui, o
# próprio ArgoCD assume: tudo que existe em gitops/ é sincronizado automaticamente
# (self-heal + prune ligados).
#
# Por que kubectl_manifest e não kubernetes_manifest (hashicorp/kubernetes): o recurso
# `kubernetes_manifest` do provider oficial valida a CRD do objeto (aqui, "Application" do
# argoproj.io) contra a API do cluster NO MOMENTO DO PLAN - mas essa CRD só existe depois que
# o Helm instala o ArgoCD, criando uma dependência circular impossível de resolver num único
# `terraform plan`. `kubectl_manifest` não faz essa validação client-side, então tolera aplicar
# o Application antes/junto da instalação do CRD (com o depends_on abaixo garantindo a ordem
# real de apply).

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

# Credencial do repositório GitOps, registrada como Secret seguindo a convenção do ArgoCD
# (label argocd.argoproj.io/secret-type=repository) - necessária porque o repositório é
# privado. Declarada aqui via Terraform (não via `argocd repo add` manual) para manter a
# regra de ouro de "nada de configuração manual fora de IaC/GitOps".
resource "kubernetes_secret" "repo_credentials" {
  count = var.git_repo_token != "" ? 1 : 0

  metadata {
    name      = "gitops-repo-credentials"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = var.git_repo_username
    password = var.git_repo_token
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [yamlencode({
    server = {
      # Padrão ClusterIP (acesso via `kubectl port-forward`) - sem custo nem exposição.
      # Para a gravação da demo, `server_service_type = "LoadBalancer"` +
      # `server_lb_source_ranges` (restrito ao IP de quem grava) sobem um ELB Classic.
      service = merge(
        { type = var.server_service_type },
        length(var.server_lb_source_ranges) > 0 ? { loadBalancerSourceRanges = var.server_lb_source_ranges } : {}
      )
    }
    configs = {
      params = {
        "server.insecure" = true # simplifica acesso via port-forward/Ingress interno no hackathon
      }
    }
  })]
}

resource "kubectl_manifest" "root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "solidarytech-root"
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.target_revision
        path           = var.gitops_root_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd]
}
