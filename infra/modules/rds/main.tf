# Uma única instância RDS Postgres hospedando os 2 bancos (ngo_db, donation_db) via
# multiplas databases lógicas - decisão de FinOps: 2 instâncias `db.t3.micro` custariam o
# dobro por ~nenhum ganho de isolamento real neste estágio (ver docs/FINOPS-FORECAST.md).
# Isolamento lógico (db diferente + usuário/schema) é suficiente para o hackathon.
#
# `ngo_db` é criado pelo próprio RDS (`db_name`). `donation_db` é criado por um Job do
# Kubernetes (PreSync hook do ArgoCD, ver gitops/apps/donation-service/db-init-job.yaml) -
# mantém a criação de schema dentro do fluxo GitOps, sem psql manual e sem exigir que quem
# roda `terraform apply` tenha rede até dentro da VPC privada.

resource "aws_security_group" "rds" {
  name_prefix = "${var.identifier}-"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.identifier}-sg" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "allow_postgres_from_eks" {
  # for_each por índice (não por valor): o SG do EKS só é conhecido após o apply do módulo
  # eks nesta mesma execução - toset(var.allowed_security_group_ids) quebraria o plan porque
  # os VALORES do set ficariam "known after apply". Índices de lista são conhecidos em plan
  # time mesmo quando os valores não são; só as chaves do for_each precisam ser estáticas.
  for_each                 = { for idx, sg_id in var.allowed_security_group_ids : idx => sg_id }
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = each.value
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # usa a chave gerenciada padrão aws/rds (sem KMS custom)

  db_name  = "ngo_db"
  username = var.master_username
  password = var.master_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"
  deletion_protection     = false # true em produção real; false aqui para permitir destroy no fim do hackathon
  skip_final_snapshot     = true
  copy_tags_to_snapshot   = true

  performance_insights_enabled = false # custo extra - não justificado no volume do hackathon

  tags = var.tags
}
