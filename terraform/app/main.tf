# ==============================================================================
# Réseau (VPC)
# Crée le VPC, les subnets publics et privés, les tables de routage,
# la passerelle Internet et les passerelles NAT.
# ==============================================================================
module "vpc" {
  source = "../modules/vpc"

  # Utilise les zones de disponibilité de la région configurée
  azs = var.azs

  # Tags spécifiques pour que EKS puisse découvrir les subnets
  # pour les Load Balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ==============================================================================
# Groupe de Sécurité pour RDS
# Crée un groupe de sécurité pour l'instance RDS.
# Pour l'instant, il n'autorise aucune connexion entrante pour plus de sécurité.
# Nous pourrons y ajouter des règles plus tard (ex: autoriser le trafic depuis EKS).
# ==============================================================================
module "rds_sg" {
  source = "../modules/sg"

  name   = "rds-sg"
  vpc_id = module.vpc.vpc_id

  # Autorise le trafic entrant depuis les noeuds EKS sur le port de la base de données.
  ingress_rules = [
    {
      from_port                = 5432 # Port PostgreSQL
      to_port                  = 5432 # Port PostgreSQL
      protocol                 = "tcp"
      source_security_group_id = module.eks.node_security_group_id
      description              = "Allow DB access from EKS nodes"
    }
  ]
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "RDS Subnet Group"
  }
}

module "rds" {
  source = "../modules/rds"

  db_identifier          = "main-db"
  db_name                = "odoo" # Nom de la base de données initiale
  db_username            = "admin"
  db_password            = "password" # A remplacer par un secret
  db_engine_version      = "16.6"   # Spécifie une version valide pour PostgreSQL
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  db_vpc_security_group_ids = [module.rds_sg.security_group_id]
}

# ==============================================================================
# Kubernetes (EKS)
# Déploie un cluster EKS dans le VPC et les subnets privés créés précédemment.
# ==============================================================================
module "eks" {
  source = "../modules/eks"

  cluster_name       = "main-cluster"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}

# ==============================================================================
# Configuration Kubernetes
# Configure le fournisseur Kubernetes pour qu'il puisse interagir avec le
# cluster EKS créé ci-dessus.
# ==============================================================================

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

# ==============================================================================
# Création de l'espace de noms Kubernetes
# Crée l'espace de noms "ic-webapp" dans lequel les ressources de l'application
# seront déployées.
# ==============================================================================
resource "kubernetes_namespace_v1" "app_namespace" {
  metadata {
    name = "ic-webapp"
  }
}
# ==============================================================================
# Création du ConfigMap Odoo
# Crée dynamiquement le ConfigMap pour Odoo en utilisant l'adresse de
# l'instance RDS provisionnée par Terraform.
# ==============================================================================
resource "kubernetes_config_map_v1" "odoo_config" {
  metadata {
    name      = "odoo-config"
    namespace = "ic-webapp"
  }
  depends_on = [
    kubernetes_namespace_v1.app_namespace
  ]
  data = {
    HOST = module.rds.db_instance_address # Récupération dynamique de l'adresse RDS
    USER = module.rds.db_username        # Récupération dynamique de l'utilisateur
  }
}

# ==============================================================================
# IAM Role for Service Account (IRSA) pour AWS Load Balancer Controller
# Crée un rôle IAM que le Service Account du Load Balancer Controller utilisera.
# ==============================================================================
module "aws_load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.28.0" # Version la plus récente

  role_name_prefix = "alb-controller-"

  # Attache la politique IAM nécessaire pour le contrôleur
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      # Le chart Helm déploie le service account dans kube-system par défaut
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Name = "iam-role-alb-controller"
  }
}

# ==============================================================================
# Helm Release: AWS Load Balancer Controller
# Installe le contrôleur via Helm, en utilisant le rôle IAM créé ci-dessus.
# ==============================================================================
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.10.1" # Version la plus récente et stable

  # Attend que le rôle IAM soit créé avant de tenter d'installer le chart
  depends_on = [module.aws_load_balancer_controller_irsa]

  # Regroupe toutes les valeurs pour une meilleure lisibilité.
  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      vpcId       = module.vpc.vpc_id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          # Annotation pour lier le Service Account au rôle IAM (IRSA)
          "eks.amazonaws.com/role-arn" = module.aws_load_balancer_controller_irsa.iam_role_arn
        }
      }
    })
  ]
}
