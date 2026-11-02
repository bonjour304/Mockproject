resource "aws_ecr_repository" "app" {
  for_each     = toset(["frontend", "backend"])
  name         = "${local.name}/${each.key}"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}

output "cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "s3_endpoint_id" { value = aws_vpc_endpoint.s3.id }
output "rds_endpoint" { value = aws_db_instance.this.address }
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
output "ecr_urls" { value = { for k, r in aws_ecr_repository.app : k => r.repository_url } }
