# ─────────────────────────────────────────────────────────────────────────────
# main.tf — Provider & données partagées
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = var.project_prefix
    }
  }
}

# ── Données globales ──────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

# ALB existant — réutilisé pour toutes les applications
data "aws_lb" "shared" {
  name = var.alb_name
}

# Listener HTTPS 443 de l'ALB partagé
data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 443
}

# Listener HTTP 80 de l'ALB partagé (redirect)
data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 80
}

# VPC de l'ALB partagé
data "aws_vpc" "main" {
  id = data.aws_lb.shared.vpc_id
}

# Subnets publics du VPC (utilisés par les tâches ECS Fargate)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  vpc_id     = data.aws_vpc.main.id

  alb_apps = {
    for key, app in var.apps : key => app
    if app.enable_alb
  }

  autoscaling_apps = {
    for key, app in var.apps : key => app
    if app.enable_autoscaling
  }

  # Subnets spécifiques pour staging (limité aux 2 subnets actuels dans AWS)
  staging_subnets = [
    "subnet-092153fd436ef0ee2",
    "subnet-06e5ed24a84c595ea"
  ]

  prod_subnets = [
    "subnet-092153fd436ef0ee2",
    "subnet-06e5ed24a84c595ea"
  ]
}
