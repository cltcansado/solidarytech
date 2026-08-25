output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

# O EKS cria (e anexa automaticamente aos ENIs dos node groups gerenciados) um "cluster
# security group" PRÓPRIO, DIFERENTE do SG customizado que passamos em vpc_config.security_
# group_ids (aws_security_group.cluster — que só é usado pelos ENIs do control plane, não
# pelos nós). Módulos como rds/redis usam este output para liberar ingress a partir dos
# nós — usar o SG errado (o customizado) faz o tráfego dos pods chegar com um SG que nunca
# foi liberado, e a conexão trava em timeout (não em "connection refused").
output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "custom_cluster_security_group_id" {
  description = "O SG customizado (aws_security_group.cluster), anexado só ao control plane — não usar para regras de acesso a partir dos nós/pods."
  value       = aws_security_group.cluster.id
}
