#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/dev-k3d"

test -x "$script"
grep -Fq 'case "$command" in' "$script"
grep -Fq '  destroy)' "$script"
grep -Fq 'terraform -chdir="$gitops" destroy' "$script"
grep -Fq 'terraform -chdir="$networking" destroy' "$script"
grep -Fq 'terraform -chdir="$cluster" destroy' "$script"

# Destruction order must retain the K3d API until its consumers are deleted.
gitops_line=$(grep -nF 'terraform -chdir="$gitops" destroy' "$script" | cut -d: -f1)
networking_line=$(grep -nF 'terraform -chdir="$networking" destroy' "$script" | cut -d: -f1)
cluster_line=$(grep -nF 'terraform -chdir="$cluster" destroy' "$script" | cut -d: -f1)
test "$gitops_line" -lt "$networking_line"
test "$networking_line" -lt "$cluster_line"

printf 'PASS: dev-k3d exposes a single ordered destroy entrypoint.\n'
