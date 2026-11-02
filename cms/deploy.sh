#!/usr/bin/env bash
# Dung toan bo lab: Terraform -> add-on -> monitoring -> image v1 -> Jenkins + ArgoCD
# Cach chay:  REPO_URL=https://github.com/<user>/<repo>.git ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${REPO_URL:?Can REPO_URL dang https://github.com/<user>/<repo>.git}"
TF="terraform -chdir=iac/terraform"
REGION=ap-southeast-1

# Mat khau admin tu sinh, luu o .secrets/ (khong dua len Git)
mkdir -p .secrets && chmod 700 .secrets
for f in grafana jenkins; do
  [ -s .secrets/$f ] || openssl rand -hex 12 > .secrets/$f
done

echo "== Terraform apply (~20 phut)"
$TF init -input=false -no-color >/dev/null
$TF apply -auto-approve -input=false -no-color > tf-apply.log 2>&1 || { tail -25 tf-apply.log; exit 1; }
grep 'Apply complete' tf-apply.log
CLUSTER=$($TF output -raw cluster_name)
VPC_ID=$($TF output -raw vpc_id)
RDS=$($TF output -raw rds_endpoint)
DBPW=$($TF output -raw db_password)

echo "== kubeconfig"
aws eks update-kubeconfig --region $REGION --name $CLUSTER >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl apply -f k8s-gp3.yaml

echo "== AWS Load Balancer Controller, metrics-server, Cluster Autoscaler"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName=$CLUSTER --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION --set vpcId=$VPC_ID --wait --timeout 10m >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --wait >/dev/null
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
  --set autoDiscovery.clusterName=$CLUSTER --set awsRegion=$REGION \
  --set rbac.serviceAccount.create=true --set rbac.serviceAccount.name=cluster-autoscaler \
  --set image.tag=v1.34.5 --wait >/dev/null

echo "== VictoriaMetrics + Grafana"
helm upgrade --install vms vm/victoria-metrics-k8s-stack -n monitoring --create-namespace \
  -f monitoring/vm-values.yaml --set grafana.adminPassword="$(cat .secrets/grafana)" \
  --wait --timeout 15m >/dev/null

echo "== Image ban dau len ECR (tag dang ghi trong values-*.yaml)"
REG=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$REGION.amazonaws.com
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG >/dev/null
TAGS=$(for e in dev staging prod; do yq '.image.tag' helm/cms-chart/values-$e.yaml; done | sort -u)
for app in backend frontend; do
  docker buildx build --platform linux/amd64 -q -t local/$app source/$app --load >/dev/null
  for t in $TAGS; do docker tag local/$app $REG/cms-minh/$app:$t; docker push -q $REG/cms-minh/$app:$t; done
done

echo "== Database va Secret cho 3 moi truong"
kubectl run psql --rm -i --restart=Never --image=postgres:16-alpine \
  --env=PGPASSWORD="$DBPW" --env=PGSSLMODE=require -- sh -c \
  "for d in cms_dev cms_staging; do psql -h $RDS -U cmsadmin -d cms -tc \"SELECT 1 FROM pg_database WHERE datname='\$d'\" | grep -q 1 || psql -h $RDS -U cmsadmin -d cms -c \"CREATE DATABASE \$d\"; done" >/dev/null
for e in dev staging prod; do
  db=cms_$e; [ $e = prod ] && db=cms
  kubectl create namespace cms-$e --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n cms-$e create secret generic db-credentials \
    --from-literal=DB_HOST=$RDS --from-literal=DB_USER=cmsadmin \
    --from-literal=DB_PASSWORD="$DBPW" --from-literal=DB_NAME=$db --from-literal=DB_SSL=true \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

echo "== Cho ban tao 2 Secret chua GitHub token (cicd/github-token, argocd/repo-ilovehk)"
kubectl create namespace cicd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "WAITING_FOR_SECRETS"
until kubectl -n cicd get secret github-token >/dev/null 2>&1 && \
      kubectl -n argocd get secret repo-ilovehk >/dev/null 2>&1; do sleep 10; done
echo "SECRETS_OK"

echo "== Jenkins"
helm upgrade --install jenkins jenkins/jenkins -n cicd -f jenkins/values.yaml \
  --set controller.admin.password="$(cat .secrets/jenkins)" \
  --set-string 'controller.containerEnv[0].name=REPO_URL' \
  --set-string "controller.containerEnv[0].value=$REPO_URL" \
  --wait --timeout 15m >/dev/null

echo "== ArgoCD + ApplicationSet"
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd/values.yaml --wait --timeout 10m >/dev/null
sed "s#__REPO_URL__#$REPO_URL#" argocd/applicationset.yaml | kubectl apply -f -

echo "== Cho 3 moi truong Synced/Healthy va ALB"
for e in dev staging prod; do
  for i in $(seq 1 60); do
    s=$(kubectl -n argocd get application cms-$e -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [ "$s" = "Synced/Healthy" ] && break; sleep 10
  done
  for i in $(seq 1 60); do
    ALB=$(kubectl -n cms-$e get ingress cms -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$ALB" ] && curl -sf "http://$ALB/api/health" >/dev/null && break; sleep 10
  done
  echo "ENV $e: $s  http://$ALB"
done
kubectl -n argocd get applications
echo DEPLOY_DONE
