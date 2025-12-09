output "node_security_group_id" {
  description = "ID of the security group attached to the EKS worker nodes."
  value       = module.eks.node_security_group_id
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster's Kubernetes API."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "The URL of the OIDC identity provider."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider."
  value       = module.eks.oidc_provider_arn
}