# ─────────────────────────────────────────────────────────────────────────────
# dns_acm.tf — Certificats ACM + enregistrements DNS Route 53
#
# Chaque app peut utiliser sa propre hosted zone (champ hosted_zone_name).
# Si hosted_zone_name est vide, la zone globale (var.hosted_zone_name) est utilisée.
# ─────────────────────────────────────────────────────────────────────────────

# ── Hosted zones — résolution des zones par app ───────────────────────────────

# Collecte les noms de zones uniques nécessaires (globale + zones custom des apps)
locals {
  # Ensemble dédupliqué des hosted zone names requis
  all_zone_names = toset(concat(
    [var.hosted_zone_name],
    [for k, v in local.alb_apps : v.hosted_zone_name if v.hosted_zone_name != ""]
  ))

  # Map app_key → zone_id effectif
  app_zone_ids = {
    for k, v in local.alb_apps : k =>
    v.hosted_zone_name != "" && v.hosted_zone_name != var.hosted_zone_name
    ? data.aws_route53_zone.extra[v.hosted_zone_name].zone_id
    : data.aws_route53_zone.main.zone_id
  }
}

# Lookup des zones supplémentaires (hors zone globale)
data "aws_route53_zone" "extra" {
  for_each = toset([
    for k, v in local.alb_apps : v.hosted_zone_name
    if v.hosted_zone_name != "" && v.hosted_zone_name != var.hosted_zone_name
  ])

  name         = each.value
  private_zone = false
}

# ── Certificats ACM production ────────────────────────────────────────────────

resource "aws_acm_certificate" "prod" {
  for_each = local.alb_apps

  domain_name       = each.value.prod_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${each.value.name}-prod-cert"
    App  = each.value.name
    Env  = "prod"
  }
}

resource "aws_route53_record" "prod_cert_validation" {
  for_each = {
    for item in flatten([
      for app_key, app in local.alb_apps : [
        for dvo in aws_acm_certificate.prod[app_key].domain_validation_options : {
          key     = "${app_key}-${dvo.domain_name}"
          app_key = app_key
          name    = dvo.resource_record_name
          record  = dvo.resource_record_value
          type    = dvo.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.app_zone_ids[each.value.app_key]
}

resource "aws_acm_certificate_validation" "prod" {
  for_each = local.alb_apps

  certificate_arn = aws_acm_certificate.prod[each.key].arn

  depends_on = [aws_route53_record.prod_cert_validation]
}

# ── Certificats ACM staging ───────────────────────────────────────────────────

resource "aws_acm_certificate" "staging" {
  for_each = local.alb_apps

  domain_name       = each.value.staging_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${each.value.name}-staging-cert"
    App  = each.value.name
    Env  = "staging"
  }
}

resource "aws_route53_record" "staging_cert_validation" {
  for_each = {
    for item in flatten([
      for app_key, app in local.alb_apps : [
        for dvo in aws_acm_certificate.staging[app_key].domain_validation_options : {
          key     = "${app_key}-${dvo.domain_name}"
          app_key = app_key
          name    = dvo.resource_record_name
          record  = dvo.resource_record_value
          type    = dvo.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.app_zone_ids[each.value.app_key]
}

resource "aws_acm_certificate_validation" "staging" {
  for_each = local.alb_apps

  certificate_arn = aws_acm_certificate.staging[each.key].arn

  depends_on = [aws_route53_record.staging_cert_validation]
}

# ── Enregistrements DNS (alias vers l'ALB) ────────────────────────────────────

resource "aws_route53_record" "prod" {
  for_each = local.alb_apps

  zone_id = local.app_zone_ids[each.key]
  name    = each.value.prod_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.shared.dns_name
    zone_id                = data.aws_lb.shared.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "staging" {
  for_each = local.alb_apps

  zone_id = local.app_zone_ids[each.key]
  name    = each.value.staging_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.shared.dns_name
    zone_id                = data.aws_lb.shared.zone_id
    evaluate_target_health = true
  }
}
