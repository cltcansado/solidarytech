# ElastiCache Redis — provisionado para atender o item "Amazon ElastiCache" da fundação de
# infra, disponível como camada de cache. Deliberadamente NÃO usado ainda no caminho crítico
# do donation-service nesta entrega: introduzir uma nova
# dependência no Hot Path sem um ciclo de teste de carga dedicado é um risco de confiabilidade
# maior do que o ganho de latência neste estágio. Fica pronto para o `ngo-service` (cache-aside
# em GET /ngos) como próximo passo natural de rightsizing/performance.

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_id}-"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_id}-sg" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "allow_redis_from_eks" {
  # ver comentário equivalente em modules/rds/main.tf: for_each por índice, não por valor.
  for_each                 = { for idx, sg_id in var.allowed_security_group_ids : idx => sg_id }
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = each.value
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_cluster" "this" {
  cluster_id         = var.cluster_id
  engine             = "redis"
  engine_version     = "7.1"
  node_type          = var.node_type
  num_cache_nodes    = 1
  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  tags = var.tags
}
