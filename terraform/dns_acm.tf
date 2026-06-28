# ─────────────────────────────────────────────────────────────────────────────
# dns_acm.tf — Certificats ACM + enregistrements DNS Route 53
# Un certificat par environnement par application.
# ─────────────────────────────────────────────────────────────────────────────

# ── Certificats ACM production ────────────────────────────────────────────────

resource "aws_acm_certificate" "prod" {
  for_each = var.apps

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
      for app_key, app in var.apps : [
        for dvo in aws_acm_certificate.prod[app_key].domain_validation_options : {
          key    = "${app_key}-${dvo.domain_name}"
          name   = dvo.resource_record_name
          record = dvo.resource_record_value
          type   = dvo.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "prod" {
  for_each = var.apps

  certificate_arn = aws_acm_certificate.prod[each.key].arn
  validation_record_fqdns = [
    for record in aws_route53_record.prod_cert_validation :
    record.fqdn
    if startswith(record.name, trimsuffix(each.value.prod_domain, ".${var.hosted_zone_name}"))
  ]
}

# ── Certificats ACM staging ───────────────────────────────────────────────────

resource "aws_acm_certificate" "staging" {
  for_each = var.apps

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
      for app_key, app in var.apps : [
        for dvo in aws_acm_certificate.staging[app_key].domain_validation_options : {
          key    = "${app_key}-${dvo.domain_name}"
          name   = dvo.resource_record_name
          record = dvo.resource_record_value
          type   = dvo.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "staging" {
  for_each = var.apps

  certificate_arn = aws_acm_certificate.staging[each.key].arn
  validation_record_fqdns = [
    for record in aws_route53_record.staging_cert_validation :
    record.fqdn
    if startswith(record.name, trimsuffix(each.value.staging_domain, ".${var.hosted_zone_name}"))
  ]
}

# ── Enregistrements DNS (alias vers l'ALB) ────────────────────────────────────

resource "aws_route53_record" "prod" {
  for_each = var.apps

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.prod_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.shared.dns_name
    zone_id                = data.aws_lb.shared.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "staging" {
  for_each = var.apps

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.staging_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.shared.dns_name
    zone_id                = data.aws_lb.shared.zone_id
    evaluate_target_health = true
  }
}
