module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                                     = "${local.name}-eks"
  kubernetes_version                       = "1.34"
  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true
  cloudwatch_log_group_retention_in_days   = 1

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver     = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["m7i-flex.large"] # Free plan khong cho t3.medium
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }
}

module "lbc_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${local.name}-lbc"
  attach_aws_lb_controller_policy = true
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${local.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

module "cluster_autoscaler_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                             = "${local.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
  }
}

# Jenkins agent push ECR qua Pod Identity, khong luu access key trong Jenkins
module "jenkins_agent_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.name}-jenkins-agent"
  additional_policy_arns = {
    ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  }
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "cicd"
      service_account = "jenkins-agent"
    }
  }
}
