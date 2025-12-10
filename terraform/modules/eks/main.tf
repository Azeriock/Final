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
# aws-load-balancer-controller = {
#   addon_version = "v2.7.2-eksbuild.1"
# },
    vpc-cni = {
      most_recent = true
      # Parfois nécessaire si vos subnets sont très sécurisés
      configuration_values = jsonencode({
        env = {
          # Force le CNI à utiliser l'interface interne si besoin
          AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
        }
      })
    }
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }

    aws-ebs-csi-driver = {
      most_recent = true # Ajout du driver EBS CSI
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
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

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0" # Même version que votre autre module IAM pour la cohérence

  role_name_prefix = "ebs-csi-"
  
  # C'est ici que ça change : on active la politique spécifique à EBS
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      # ATTENTION : Le nom du Service Account est standardisé par l'addon AWS
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Name = "iam-role-ebs-csi"
  }
}