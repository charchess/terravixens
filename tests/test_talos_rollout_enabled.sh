#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for env in dev staging test prod; do
  grep -A4 'variable "talos_rollout_enabled"' "$root/terraform/environments/$env/variables.tf" | grep -Fq 'default     = false'
done
echo "PASS: Talos rollout remains opt-in in every environment"
