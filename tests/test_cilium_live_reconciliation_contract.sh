#!/usr/bin/env bash
# Contract: Terraform source must reflect the observed production Cilium release.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
need() { grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1#"$ROOT/"}"; }
absent() { if grep -Fq -- "$2" "$1"; then fail "unexpected '$2' in ${1#"$ROOT/"}"; fi; }

SHARED="$ROOT/terraform/modules/shared/locals.tf"
need "$SHARED" 'cilium       = "1.20.2"'
printf 'PASS: Cilium source matches observed production release contract\n'
