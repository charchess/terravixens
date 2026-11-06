#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_root="$root/terraform/environments/dev-k3d"

for required in main.tf providers.tf versions.tf README.md; do
  test -f "$env_root/$required"
done

for retired in cluster networking gitops; do
  test ! -e "$env_root/$retired"
done

test ! -e "$root/scripts/dev-k3d"
test ! -e "$root/scripts/dev-k3d-apply.sh"

grep -Fq 'resource "k3d_cluster" "dev"' "$env_root/main.tf"
grep -Fq 'resource "local_sensitive_file" "kubeconfig"' "$env_root/main.tf"
grep -Fq 'filename             = local.kubeconfig_path' "$env_root/main.tf"
grep -Fq 'pathexpand("~/.secrets/vixens-dev/openbao-token.yaml")' "$env_root/main.tf"
! grep -R --include='*.tf' -q 'variable "kubeconfig_path"' "$env_root"

echo "PASS: dev-k3d is a single Terraform root with an internal kubeconfig"
