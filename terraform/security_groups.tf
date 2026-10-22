# ─────────────────────────────────────────────────────────────────────────────
# security_groups.tf — SG ECS par app/env
# Le trafic entrant est autorisé uniquement depuis le SG de l'ALB partagé.
# ─────────────────────────────────────────────────────────────────────────────

# Récupérer le security group de l'ALB partagé
data "aws_security_groups" "alb" {
  filter {
    name   = "tag:Name"
    values = ["${var.alb_name}-sg", var.alb_name]
  }
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# SG ECS — environnement production
resource "aws_security_group" "ecs_prod" {
  for_each = var.apps

  name        = "${each.value.name}-prod-ecs-sg"
  description = "SG ECS Fargate ${each.value.name} prod"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = each.value.enable_alb ? [true] : []

    content {
      description = "Traffic from ALB"
      from_port   = each.value.container_port
      to_port     = each.value.container_port
      protocol    = "tcp"
      # Fallback CIDR si le SG de l'ALB n'est pas taggué
      cidr_blocks     = length(data.aws_security_groups.alb.ids) == 0 ? ["0.0.0.0/0"] : []
      security_groups = length(data.aws_security_groups.alb.ids) > 0 ? data.aws_security_groups.alb.ids : []
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${each.value.name}-prod-ecs-sg"
    App  = each.value.name
    Env  = "prod"
  }
}

# SG ECS — environnement staging
resource "aws_security_group" "ecs_staging" {
  for_each = var.apps

  name        = "${each.value.name}-staging-ecs-sg"
  description = "SG ECS Fargate ${each.value.name} staging"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = each.value.enable_alb ? [true] : []

    content {
      description     = "Traffic from ALB"
      from_port       = each.value.container_port
      to_port         = each.value.container_port
      protocol        = "tcp"
      cidr_blocks     = length(data.aws_security_groups.alb.ids) == 0 ? ["0.0.0.0/0"] : []
      security_groups = length(data.aws_security_groups.alb.ids) > 0 ? data.aws_security_groups.alb.ids : []
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${each.value.name}-staging-ecs-sg"
    App  = each.value.name
    Env  = "staging"
  }
}
