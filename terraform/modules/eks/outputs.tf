output "node_security_group_id" {
  description = "ID of the security group attached to the EKS worker nodes."
  value       = module.eks.node_security_group_id
}