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

# ==============================================================================
# Base de données (RDS)
# Déploie une instance de base de données PostgreSQL dans les subnets privés.
# ==============================================================================
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
