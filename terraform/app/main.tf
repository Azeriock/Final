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
    "kubernetes.io/cluster/main-cluster" = "shared"
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
  db_username            = "odoo"
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
  

  # Autorise le rôle IAM du pipeline CI/CD à administrer le cluster via les Access Entries.
  # C'est la méthode moderne pour gérer les permissions d'accès au cluster.
  access_entries = {
    mon_acces_perso = {
      principal_arn = "arn:aws:iam::169332976667:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_41a1a8fb17b69510"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    cicd_runner = {
      principal_arn = var.cicd_iam_role_arn
      user_name     = "cicd-runner"

      # On associe la politique d'admin officielle AWS
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
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

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = null # null = utilise la version par défaut pour la version K8s
  resolve_conflicts_on_create = "OVERWRITE" # Vital pour les recréations
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

  # On force explicitement l'ordre :
  # L'addon ne doit se lancer que si le cluster ET les nodes sont là
  # (Les drivers ont besoin de nodes pour tourner)
  depends_on = [
    module.eks,
    module.ebs_csi_irsa_role
  ]
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
  version = "5.60.0"

  role_name_prefix = "alb-controller-"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    # Le nom "main" est arbitraire ici, mais le contenu est strict
    main = {
      # 🚨 OBLIGATOIRE : Vous devez fournir l'ARN explicitement
      provider_arn               = module.eks.oidc_provider_arn
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
  replace         = true  # Force la réutilisation du nom si conflit
  atomic          = true # Si ça plante, ça annule tout automatiquement
  cleanup_on_fail = true # Nettoie l'installation en cas d'échec

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

# Appel du module local
module "ssl_certificate" {
  source = "../modules/certificate"

  # On passe les variables
  domain_name = "nuages.click"
  environment = "prod"
}

# On demande à AWS : "Trouve-moi le Load Balancer qui correspond à mon Ingress"
data "aws_lb" "ingress_alb" {
  tags = {
    # C'est la signature automatique du contrôleur AWS
    "ingress.k8s.aws/stack" = "ic-webapp/main-ingress"
  }
}

data "aws_route53_zone" "nuages" {
  name = "nuages.click"
}

locals {
  # Ajoutez simplement un nom ici pour créer un nouveau sous-domaine !
  app_subdomains = toset([
    "odoo",
    "pgadmin",
    "ic-webapp"
    
  ])
}

resource "aws_route53_record" "apps" {
  # on boucle sur la liste
  for_each = local.app_subdomains
  zone_id = data.aws_route53_zone.nuages.zone_id
  name    = "${each.key}.nuages.click" 
  type    = "A"

  alias {
    # On utilise toujours le même Load Balancer (récupéré dynamiquement)
    name                   = data.aws_lb.ingress_alb.dns_name
    zone_id                = data.aws_lb.ingress_alb.zone_id
    evaluate_target_health = true
  }
}