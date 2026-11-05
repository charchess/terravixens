#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cluster="${root}/terraform/environments/dev-k3d/cluster"
networking="${root}/terraform/environments/dev-k3d/networking"
gitops="${root}/terraform/environments/dev-k3d/gitops"

for path in "$cluster" "$networking" "$gitops"; do
  test -d "$path"
done

grep -Fq 'resource "k3d_cluster" "dev"' "$cluster/main.tf"
grep -Fq -- '--flannel-backend=none' "$cluster/main.tf"
grep -Fq -- '--disable-network-policy' "$cluster/main.tf"
grep -Fq -- '--disable-kube-proxy' "$cluster/main.tf"
grep -Fq 'local_sensitive_file' "$cluster/main.tf"
grep -Fq 'module "cilium"' "$networking/main.tf"
grep -Fq 'name                     = "k3d"' "$networking/main.tf"
grep -Fq 'l2_announcements_enabled = false' "$networking/main.tf"
grep -Fq 'resource "terraform_data" "cilium_ready"' "$gitops/main.tf"
grep -Fq 'rollout status daemonset/cilium' "$gitops/main.tf"
printf 'PASS: dev K3d platform lifecycle contract is present.\n'
