# ─────────────────────────────────────────────────────────────────────────────
# alb_rules.tf — Target Groups ALB + Listener Rules (Host header routing)
# Le routage se fait via la valeur du Host header sur le listener HTTPS 443.
# ─────────────────────────────────────────────────────────────────────────────

# ── Target Groups ─────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "prod" {
  for_each = local.alb_apps

  name        = "${each.value.name}-prod-tg"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-299"
  }

  tags = {
    Name = "${each.value.name}-prod-tg"
    App  = each.value.name
    Env  = "prod"
  }
}

resource "aws_lb_target_group" "staging" {
  for_each = local.alb_apps

  name        = "${each.value.name}-stg-tg"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-299"
  }

  tags = {
    Name = "${each.value.name}-stg-tg"
    App  = each.value.name
    Env  = "staging"
  }
}

# ── Listener Rules HTTPS — Production ────────────────────────────────────────
# Route le trafic vers le TG prod si Host = <prod_domain>

resource "aws_lb_listener_rule" "prod" {
  for_each = local.alb_apps

  listener_arn = data.aws_lb_listener.https.arn
  priority     = each.value.prod_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.prod_domain]
    }
  }

  tags = {
    Name = "${each.value.name}-prod-rule"
    App  = each.value.name
    Env  = "prod"
  }
}

# ── Listener Rules HTTPS — Staging ───────────────────────────────────────────
# Route le trafic vers le TG staging si Host = <staging_domain>

resource "aws_lb_listener_rule" "staging" {
  for_each = local.alb_apps

  listener_arn = data.aws_lb_listener.https.arn
  priority     = each.value.staging_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.staging[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.staging_domain]
    }
  }

  tags = {
    Name = "${each.value.name}-staging-rule"
    App  = each.value.name
    Env  = "staging"
  }
}

# ── Listener Rules HTTP → HTTPS redirect ──────────────────────────────────────
# Si le listener HTTP 80 n'a pas déjà une règle de redirect globale, on peut
# en ajouter une par app. Commenter si l'ALB a déjà un redirect par défaut.

# resource "aws_lb_listener_rule" "http_redirect_prod" {
#   for_each     = var.apps
#   listener_arn = data.aws_lb_listener.http.arn
#   priority     = each.value.prod_rule_priority
#   action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }
#   condition {
#     host_header { values = [each.value.prod_domain] }
#   }
# }

# ── Attachement des certificats ACM au listener HTTPS partagé ────────────────
# L'ALB fait le SNI matching au niveau du listener (pas de la rule).
# Sans cette ressource, l'ALB présente son certificat par défaut pour tous les
# domaines inconnus → NET::ERR_CERT_COMMON_NAME_INVALID sur les domaines custom.

resource "aws_lb_listener_certificate" "prod" {
  for_each = local.alb_apps

  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.prod[each.key].certificate_arn
}

resource "aws_lb_listener_certificate" "staging" {
  for_each = local.alb_apps

  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.staging[each.key].certificate_arn
}