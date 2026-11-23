# ---------- Container registry for runtime images ----------
resource "aws_ecr_repository" "orders_api" {
  name                 = "orders-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = !var.protect_data # only allowed when tearing the lab down

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "orders_api" {
  repository = aws_ecr_repository.orders_api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
