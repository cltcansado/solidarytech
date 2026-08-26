# Módulo puramente declarativo: centraliza a política de tagging FinOps exigida pelo
# enunciado (Project=SolidaryTech, Environment=Production, CostCenter=NGO-Core) em UM
# lugar só. Toda a infra referencia `module.tags.tags` (ou o provider AWS usa `default_tags`
# com o mesmo mapa) - nunca tags soltas hardcoded espalhadas pelos módulos.
output "tags" {
  value = merge(
    {
      Project     = var.project
      Environment = var.environment
      CostCenter  = var.cost_center
      ManagedBy   = "Terraform"
    },
    var.extra_tags
  )
}
