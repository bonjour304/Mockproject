#!/usr/bin/env bash
# Don dep: xoa app qua ArgoCD (ALB), go Jenkins/monitoring (EBS), roi terraform destroy
set -uo pipefail
cd "$(dirname "$0")"
REGION=ap-southeast-1

echo "== Xoa ApplicationSet -> ArgoCD xoa 3 app va ALB"
kubectl -n argocd delete applicationset cms --wait=true --timeout=5m 2>/dev/null
for i in $(seq 1 30); do
  n=$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "0" ] && break; sleep 10
done
helm uninstall cms -n cms-prod --wait 2>/dev/null   # neu tung cai tay

echo "== Go Jenkins, ArgoCD, monitoring va PVC"
helm uninstall jenkins -n cicd --wait 2>/dev/null
helm uninstall argocd -n argocd --wait 2>/dev/null
helm uninstall vms -n monitoring --wait 2>/dev/null
kubectl -n cicd delete pvc --all --wait=true --timeout=5m 2>/dev/null
kubectl -n monitoring delete pvc --all --wait=true --timeout=5m 2>/dev/null

echo "== Cho ALB bi xoa"
for i in $(seq 1 30); do
  n=$(aws elbv2 describe-load-balancers --region $REGION \
      --query "length(LoadBalancers[?starts_with(LoadBalancerName, 'k8s-cms')])" --output text)
  [ "$n" = "0" ] && break; sleep 10
done
echo "ALB con lai: $n"

echo "== Cho EBS cua PVC bi xoa"
for i in $(seq 1 30); do
  v=$(aws ec2 describe-volumes --region $REGION --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name \
      --query 'length(Volumes)' --output text)
  [ "$v" = "0" ] && break; sleep 10
done
echo "EBS PVC con lai: $v"

helm uninstall cluster-autoscaler aws-load-balancer-controller metrics-server -n kube-system 2>/dev/null

echo "== terraform destroy"
terraform -chdir=iac/terraform destroy -auto-approve -input=false -no-color
echo "DESTROY_EXIT=$?"

echo "== Kiem tra con sot (nen rong)"
aws eks list-clusters --region $REGION --query clusters --output text
aws rds describe-db-instances --region $REGION --query 'DBInstances[].DBInstanceIdentifier' --output text
aws ec2 describe-nat-gateways --region $REGION --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text
aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[].LoadBalancerName' --output text
echo DESTROY_DONE
