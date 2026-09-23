#!/usr/bin/env bash
# Contract: Argo bootstrap seeds hand ownership to ArgoCD after creation.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FILE="$ROOT/terraform/modules/argocd/main.tf"
python3 - "$ROOT" "$FILE" <<'PY'
import sys
ROOT,FILE=sys.argv[1:]
text=open(FILE).read()
expected=[
 ('kubectl_manifest','argocd_params_bootstrap'),
 ('kubectl_manifest','argocd_cm_anonymous'),
 ('kubectl_manifest','argocd_rbac_cm_anonymous'),
 ('kubectl_manifest','argocd_root_app'),
]
if 'variable "bootstrap_seed_enabled"' not in open(f"{ROOT}/terraform/modules/argocd/variables.tf").read():
 raise SystemExit('FAIL: Argo bootstrap seed gate is not declared')
if 'bootstrap_seed_enabled = var.argocd_bootstrap_seed_enabled' not in open(f"{ROOT}/terraform/modules/environment/argocd.tf").read():
 raise SystemExit('FAIL: environment does not propagate the Argo bootstrap seed gate')
if 'argocd_bootstrap_seed_enabled = false' not in open(f"{ROOT}/terraform/environments/prod/main.tf").read():
 raise SystemExit('FAIL: production does not hand off Argo bootstrap seeds')
for required in [
 'resource "null_resource" "argocd_crds" {\n  count = var.bootstrap_seed_enabled ? 1 : 0',
 'resource "null_resource" "argocd_pre_destroy_cleanup" {\n  count = var.bootstrap_seed_enabled ? 1 : 0',
 'for_each  = var.bootstrap_seed_enabled ? toset(local.argocd_manifests) : toset([])',
 'resource "kubectl_manifest" "argocd_root_app" {\n  count = var.bootstrap_seed_enabled ? 1 : 0',
]:
 if required not in text:
  raise SystemExit(f'FAIL: bootstrap seed is not gated: {required}')
for typ,name in expected:
 start=text.index(f'resource "{typ}" "{name}" {{')
 i=start; depth=0; end=None
 for i in range(start,len(text)):
  if text[i]=='{': depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0: end=i+1; break
 block=text[start:end]
 if 'ignore_changes = all' not in block:
  raise SystemExit(f'FAIL: {typ}.{name} does not hand off after bootstrap')
start=text.index('resource "kubernetes_namespace" "argocd" {')
i=start; depth=0; end=None
for i in range(start,len(text)):
 if text[i]=='{': depth+=1
 elif text[i]=='}':
  depth-=1
  if depth==0: end=i+1; break
namespace_block=text[start:end]
if 'ignore_changes = [metadata, wait_for_default_service_account]' not in namespace_block:
 raise SystemExit('FAIL: argocd namespace does not ignore controller metadata and client wait state')
print('PASS: Argo bootstrap seeds hand off to GitOps')
PY
