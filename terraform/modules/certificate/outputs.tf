output "certificate_arn" {
  description = "L'ARN du certificat validé"
  value       = module.acm.acm_certificate_arn
}