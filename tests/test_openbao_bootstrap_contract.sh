#!/usr/bin/env bash
# Contract test for the out-of-Git OpenBao bootstrap path.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
need() { grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1#"$ROOT/"}"; }

ARG="$ROOT/terraform/modules/argocd"
ENV="$ROOT/terraform/modules/environment"
PROD="$ROOT/terraform/environments/prod"

need "$ARG/variables.tf" 'variable "openbao_bootstrap_token_path"'
need "$ARG/main.tf" 'resource "kubernetes_namespace" "external_secrets"'
need "$ARG/main.tf" 'resource "kubernetes_secret_v1" "openbao_token"'
need "$ARG/main.tf" 'wait_for_service_account_token = false'
need "$ARG/main.tf" 'fileexists(var.openbao_bootstrap_token_path)'
need "$ARG/main.tf" 'external-secrets/openbao-token'
need "$ARG/main.tf" 'kubernetes_secret_v1.openbao_token'
need "$ENV/argocd.tf" 'openbao_bootstrap_token_path = var.paths.openbao_bootstrap_token'
need "$ENV/variables.tf" 'openbao_bootstrap_token = string'
need "$PROD/variables.tf" 'openbao_bootstrap_token = optional(string, "../../../.secrets/prod/openbao-token.yaml")'
need "$PROD/variables.tf" 'openbao_bootstrap_token = "../../../.secrets/prod/openbao-token.yaml"'
need "$PROD/imports.tf" 'kubernetes_namespace.external_secrets'
need "$PROD/imports.tf" 'kubernetes_secret_v1.openbao_token'
printf 'PASS: OpenBao bootstrap Terraform contract\n'
