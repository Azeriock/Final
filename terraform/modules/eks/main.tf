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

  # Contrôle l'accès public au point de terminaison du cluster.
  endpoint_public_access = true

  # Active la gestion de l'AWS Load Balancer Controller comme un add-on EKS.
  # Le module créera automatiquement le rôle IAM nécessaire.
  addons = {
    aws-load-balancer-controller = {
      most_recent = true # Utilise la version la plus récente de l'add-on
    },
    aws-ebs-csi-driver = {
      most_recent = true # Ajout du driver EBS CSI
    }
  }

  eks_managed_node_groups = {
    main = {
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      instance_types = var.node_group_instance_types
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