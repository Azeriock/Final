variable "domain_name" {
  description = "Le nom de domaine principal (ex: nuages.click)"
  type        = string
}

variable "environment" {
  description = "L'environnement (dev, prod, stag)"
  type        = string
  default     = "prod"
}