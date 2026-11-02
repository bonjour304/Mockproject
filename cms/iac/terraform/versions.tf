terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Owner = var.owner, Project = "cms-mock", ManagedBy = "terraform" }
  }
}

variable "region" { default = "ap-southeast-1" }
variable "owner" { default = "minh" }
variable "prefix" { default = "cms-minh" }
variable "rds_multi_az" { default = false }

locals {
  name = var.prefix
  azs  = ["${var.region}a", "${var.region}b"]
}
