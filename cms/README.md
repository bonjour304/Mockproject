# CMS trên AWS EKS

Mock Project DevOps – Trần Công Minh, lớp DO2605.

CMS quản lý danh mục phim (React + Node.js/Express + PostgreSQL) chạy trên Amazon EKS.
Hạ tầng dựng bằng Terraform, CI bằng Jenkins, CD theo mô hình GitOps với ArgoCD.

## Cấu trúc

| Nhóm | Thư mục / file | Nội dung |
| --- | --- | --- |
| Mã nguồn FE, BE | `source/frontend`, `source/backend` | React (Vite) + nginx; Node.js 22/Express, Dockerfile, unit test (`node:test`) |
| IaC | `iac/terraform/` | VPC 2 AZ, EKS 1.34, RDS PostgreSQL 16, ECR, Pod Identity |
| GitOps | `helm/cms-chart/`, `argocd/` | Helm chart + values dev/staging/prod; ArgoCD và ApplicationSet |
| CI/CD | `Jenkinsfile`, `jenkins/values.yaml` | Pipeline 7 stage; Jenkins cấu hình bằng JCasC |
| Monitoring | `monitoring/vm-values.yaml`, `k8s-gp3.yaml` | VictoriaMetrics + Grafana, StorageClass gp3 |
| Vận hành | `deploy.sh`, `destroy.sh` | Dựng và gỡ toàn bộ hệ thống |

## Luồng CI/CD

```
git push → Jenkins (pod agent trong EKS): Test → Build (BuildKit) → Push ECR (tag = commit SHA)
        → ghi tag vào values-dev/staging.yaml → ArgoCD sync cms-dev, cms-staging
        → duyệt tay → ghi tag vào values-prod.yaml → ArgoCD sync cms-prod
```

Jenkins không deploy trực tiếp; Git là source. Rollback = `git revert` commit đổi tag.

## Chạy local

```bash
docker run -d --name cms-db -p 5432:5432 -e POSTGRES_PASSWORD=localdev -e POSTGRES_DB=cms postgres:16
cd source/backend && npm install
DB_HOST=localhost DB_USER=postgres DB_PASSWORD=localdev DB_NAME=cms npm start   # http://localhost:8000
cd source/frontend && npm install && npm run dev                                # http://localhost:3000
```

## Dựng trên AWS

Cần AWS CLI (đã `aws configure`), Terraform, kubectl, Helm.

```bash
REPO_URL=https://github.com/bonjour304/Mockproject.git ./deploy.sh
```

Script dừng ở `WAITING_FOR_SECRETS` để người chạy tự nạp GitHub token (fine-grained, quyền Contents
Read and write trên repo này) vào 2 Secret `cicd/github-token` và `argocd/repo-ilovehk`.
Token và mật khẩu không nằm trong Git; mật khẩu Jenkins, Grafana sinh vào `.secrets/` (đã gitignore).

## Gỡ toàn bộ

```bash
./destroy.sh
```

Xóa ApplicationSet và PVC trước, chờ ALB và ổ EBS do Kubernetes tạo biến mất, rồi mới `terraform destroy`.
