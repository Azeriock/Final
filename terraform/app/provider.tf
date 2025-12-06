terraform {
  backend "s3" {
    bucket                  = "terraform-bucket-loic"
    key                     = "loic-dev.tfstate"
    region                  = "us-east-1"
    profile                 = "loic"
    dynamodb_table          = "terraform-locks"
  }
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "loic"
}