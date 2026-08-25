# Cluster EKS "cru" (sem o módulo terraform-aws-modules/eks) DE PROPÓSITO: esse módulo
# oficial tenta criar IAM roles/policies e (opcionalmente) o OIDC provider para IRSA por
# padrão, o que quebra sob as restrições da AWS Academy (iam:CreateRole/CreatePolicy/
# CreateOpenIDConnectProvider negados na LabRole). Usando os recursos aws_eks_* diretamente,
# controlamos exatamente quais chamadas IAM são feitas — nenhuma.
#
# Consequência assumida: sem IRSA. Os pods dos serviços que falam com SQS/DynamoDB usam as
# permissões da role do NÓ (LabRole), não uma role por Service Account.

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_name}-cluster-sg" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true # necessário: sem VPN/bastion, o time acessa via kubectl da máquina local
  }

  # Logs de auditoria/API já resolvem boa parte da seção de Segurança/AIOps sem custo extra
  # de ferramenta (vão para o CloudWatch Logs).
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags
}

# Launch template só para ajustar o IMDS (metadata_options) — sem isso, os pods (que rodam
# em um namespace de rede próprio via VPC CNI, não no namespace do host) não alcançam o
# metadata service da instância, porque o hop limit default (1) só permite acesso a partir
# do próprio namespace do host. QUALQUER coisa que dependa da LabRole via IMDS nos pods
# (donation-service/SQS, volunteer-service/DynamoDB, healer-service, EBS CSI driver, Velero)
# quebra sem isso — sintoma observado: "no EC2 IMDS role found" nos logs do container.
# instance_type/image_id ficam de propósito FORA do launch template: o node group continua
# controlando isso via `instance_types` (permitido pela AWS quando o launch template não
# define instance_type/image_id).
resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obrigatório
    http_put_response_hop_limit = 2          # 1 = só o host; pods precisam de 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }
}

resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ondemand"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  labels = {
    "solidarytech.io/tier" = "critical" # donation-service roda aqui (Hot Path)
  }

  tags = var.tags
}

# Node group Spot para cargas não-críticas (ngo-service, volunteer-service, stack de
# observabilidade) — recomendação prática de otimização nativa de nuvem citada no
# relatório de FinOps (docs/FINOPS-FORECAST.md).
resource "aws_eks_node_group" "spot" {
  count = var.enable_spot_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.spot_node_instance_types
  capacity_type   = "SPOT"

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 3
  }

  labels = {
    "solidarytech.io/tier" = "non-critical"
  }

  taint {
    key    = "solidarytech.io/spot"
    value  = "true"
    effect = "PREFER_NO_SCHEDULE"
  }

  tags = var.tags
}

# Sem este addon, NENHUM PersistentVolumeClaim é atendido no cluster (fica "Pending" para
# sempre) — EKS não instala o EBS CSI driver por padrão. Necessário para os volumes do
# Prometheus/Grafana/Loki (observabilidade) e do Velero (backup a nível de arquivo).
# Sem IRSA disponível (restrição AWS Academy), não é passado
# `service_account_role_arn`: o driver cai no fallback de usar a role do NÓ (LabRole) via
# IMDS, mesmo padrão já usado pelos demais componentes deste projeto.
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.on_demand]
}
