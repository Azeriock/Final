# 1. On cherche automatiquement l'ID de la zone Hosted Zone
data "aws_route53_zone" "selected" {
  name         = var.domain_name
  private_zone = false
}

# 2. On utilise le module communautaire ACM pour créer le certificat
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.0"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.selected.zone_id

  # Création automatique du wildcard (*.domaine.com)
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  wait_for_validation = true
  validation_method = "DNS"

  tags = {
    Name        = "${var.domain_name}-cert"
    Environment = var.environment
  }
}