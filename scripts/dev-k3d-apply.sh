#!/usr/bin/env bash
set -euo pipefail

# Terraform lifecycle entrypoint: K3d -> Cilium -> ArgoCD.
# Each root owns a separate state, so Kubernetes providers never initialize
# before the K3d API and its protected kubeconfig exist.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kubeconfig=${KUBECONFIG_PATH:-"$HOME/.kube/vixens-dev-k3d.yaml"}
openbao_token_path=${OPENBAO_BOOTSTRAP_TOKEN_PATH:?Set OPENBAO_BOOTSTRAP_TOKEN_PATH to the protected dev token YAML path.}

terraform -chdir="$root/terraform/environments/dev-k3d/cluster" init -reconfigure -input=false
terraform -chdir="$root/terraform/environments/dev-k3d/cluster" apply -input=false -auto-approve \
  -var="kubeconfig_path=$kubeconfig"
kubectl --kubeconfig="$kubeconfig" get --raw=/readyz >/dev/null
kubectl --kubeconfig="$kubeconfig" get nodes

terraform -chdir="$root/terraform/environments/dev-k3d/networking" init -reconfigure -input=false
terraform -chdir="$root/terraform/environments/dev-k3d/networking" apply -input=false -auto-approve \
  -var="kubeconfig_path=$kubeconfig" \
  -var="k8s_service_host=k3d-vixens-dev-server-0"
kubectl --kubeconfig="$kubeconfig" -n kube-system rollout status daemonset/cilium --timeout=10m
kubectl --kubeconfig="$kubeconfig" -n kube-system rollout status deployment/cilium-operator --timeout=10m

terraform -chdir="$root/terraform/environments/dev-k3d/gitops" init -reconfigure -input=false
terraform -chdir="$root/terraform/environments/dev-k3d/gitops" apply -input=false -auto-approve \
  -var="kubeconfig_path=$kubeconfig" \
  -var="openbao_bootstrap_token_path=$openbao_token_path" \
  -var="bootstrap_enabled=true"
kubectl --kubeconfig="$kubeconfig" -n argocd rollout status deployment/argocd-server --timeout=10m
kubectl --kubeconfig="$kubeconfig" -n argocd get application vixens-app-of-apps
kubectl --kubeconfig="$kubeconfig" get storageclass storage-rwo-delete storage-rwo-retain storage-rwx-delete storage-rwx-retain
