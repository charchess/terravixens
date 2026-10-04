#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Talos upgrade-k8s reconciles bootstrap manifests. Runtime CoreDNS is owned by
# ArgoCD, so no Terraform execution path may invoke it until an inventory-safe
# migration exists and is separately tested.
if grep -RIn --exclude-dir=.terraform 'upgrade-k8s' "$repo_root/terraform" "$repo_root/scripts"; then
  fail 'Terraform source still contains an unsafe talosctl upgrade-k8s path'
fi
if grep -RIn --exclude-dir=.git --exclude-dir=.terraform 'kubernetes_rollout_enabled' "$repo_root/terraform"; then
  fail 'deprecated Kubernetes rollout switch is still wired into Terraform'
fi

echo 'PASS: Terraform cannot replay Talos bootstrap manifests during apply'
