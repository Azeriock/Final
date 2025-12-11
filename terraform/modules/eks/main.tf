terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0" # Mise à jour pour compatibilité avec AWS provider v6

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  access_entries = var.access_entries

  # Contrôle l'accès public au point de terminaison du cluster.
  endpoint_public_access = true
  endpoint_private_access = true

  # Active la gestion de l'AWS Load Balancer Controller comme un add-on EKS.
  # Le module créera automatiquement le rôle IAM nécessaire.
  addons = {
    vpc-cni                = {
      before_compute = true
    }
    coredns                = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy             = {}
  }

  eks_managed_node_groups = {
    main = {
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      instance_types = var.node_group_instance_types
      iam_role_additional_policies = {
        # 1. Obligatoire pour que le noeud rejoigne le cluster
        AmazonEKSWorkerNodePolicy = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        
        # 2. Obligatoire pour la gestion des IPs (VPC CNI)
        AmazonEKS_CNI_Policy = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        
        # 3. Obligatoire pour télécharger les images Docker système
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        
        # Permet à SSM de fonctionner
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  tags = merge(
    {
      "Name"        = var.cluster_name
      "Environment" = "prod" # Exemple de tag standard
    },
    var.tags
  )
}