#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
coredns="$repo_root/terraform/modules/environment/coredns.tf"
argocd="$repo_root/terraform/modules/environment/argocd.tf"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Bootstrap must not leave Terraform with a remotely managed CoreDNS object.
grep -Fq 'resource "terraform_data" "coredns_bootstrap"' "$coredns" || fail 'bootstrap execution marker missing'
! grep -Fq 'resource "kubectl_manifest" "coredns_bootstrap"' "$coredns" || fail 'Terraform still owns CoreDNS as a manifest resource'
grep -Fq 'Its destroy path is intentionally empty' "$coredns" || fail 'safe state-handoff contract missing'

# Bootstrap applies a generic recursive Corefile, not domain-specific runtime DNS.
grep -Fq 'forward . ${join(" ", var.coredns_bootstrap.upstreams)}' "$coredns" || fail 'bootstrap forwarders missing'
! grep -Fq 'internal.truxonline.com:53' "$coredns" || fail 'internal runtime zone leaked into bootstrap'
! grep -Fq 'truxonline.com:53 {' "$coredns" || fail 'runtime domain zone leaked into bootstrap'

# ArgoCD must start after the bootstrap probe, and later owns the ConfigMap.
grep -Fq 'terraform_data.coredns_bootstrap' "$argocd" || fail 'ArgoCD bootstrap is not ordered after DNS bootstrap'
grep -Fq 'ArgoCD owns this ConfigMap after bootstrap' "$coredns" || fail 'ownership handoff annotation missing'

echo 'PASS: CoreDNS bootstrap is one-shot, ordered, and handoff-safe'
