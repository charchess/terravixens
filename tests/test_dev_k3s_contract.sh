#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_dir="${repo_root}/terraform/environments/dev-k3s"

[[ -f "${env_dir}/main.tf" ]]
[[ -f "${env_dir}/variables.tf" ]]
[[ -f "${env_dir}/providers.tf" ]]
[[ -f "${env_dir}/backend.tf" ]]
[[ -f "${env_dir}/versions.tf" ]]

# A K3s target must use a supplied kubeconfig and must never create or query Talos.
if grep -R -E 'talos_|module\.environment|modules/environment|modules/talos|siderolabs/talos' "${env_dir}"; then
  echo "dev-k3s must not depend on Talos resources, providers, or modules" >&2
  exit 1
fi

grep -Fq 'config_path = var.kubeconfig_path' "${env_dir}/providers.tf"
grep -Fq 'backend "local"' "${env_dir}/backend.tf"
grep -Fq 'path = "state/terraform.tfstate"' "${env_dir}/backend.tf"
grep -Fq 'storage_class_name' "${env_dir}/variables.tf"
grep -Fq 'storage-rwo-delete' "${env_dir}/variables.tf"
grep -Fq 'storage-rwo-retain' "${env_dir}/variables.tf"
grep -Fq 'environment            = var.environment' "${env_dir}/main.tf"
grep -Fq 'source = "../../modules/argocd"' "${env_dir}/main.tf"
grep -Fq 'resource "kubernetes_storage_class_v1" "local_path_contract"' "${env_dir}/main.tf"
grep -Fq '"storage-rwo-delete" = "Delete"' "${env_dir}/main.tf"
grep -Fq '"storage-rwo-retain" = "Retain"' "${env_dir}/main.tf"
grep -Fq '"storage-rwx-delete" = "Delete"' "${env_dir}/main.tf"
grep -Fq '"storage-rwx-retain" = "Retain"' "${env_dir}/main.tf"
grep -Fq 'git_repository_url' "${env_dir}/main.tf"
grep -Fq 'var.git_repository_url' "${env_dir}/main.tf"
grep -Fq 'https://github.com/charchess/vixens-core.git' "${env_dir}/variables.tf"
grep -Fq 'git_repository_url' "${repo_root}/terraform/modules/argocd/main.tf"
grep -Fq 'repoURL: ${repo_url}' "${repo_root}/terraform/manifests/argocd/root-app.yaml.tpl"

echo "PASS: dev-k3s is a K3s-only bootstrap root with isolated state."
