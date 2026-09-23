#!/usr/bin/env bash
# Existing ignored tfvars must inherit the OpenBao bootstrap path during migration.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
P="$ROOT/terraform/environments/prod/variables.tf"
grep -Fq 'openbao_bootstrap_token = optional(string, "../../../.secrets/prod/openbao-token.yaml")' "$P" || {
  printf 'FAIL: prod paths does not provide a compatible OpenBao bootstrap default\n' >&2
  exit 1
}
printf 'PASS: prod OpenBao path is backward-compatible with existing ignored tfvars\n'
