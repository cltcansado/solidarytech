resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repository_names)
  name                 = "solidarytech/${each.value}"
  image_tag_mutability = "IMMUTABLE" # rastreabilidade: tag = SHA do commit, nunca sobrescrita

  image_scanning_configuration {
    scan_on_push = true # SCA de imagem - parte da esteira DevSecOps (complementa Trivy no CI)
  }

  tags = merge(var.tags, { Component = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantém só as ${var.keep_last_n_images} imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_n_images
      }
      action = { type = "expire" }
    }]
  })
}
