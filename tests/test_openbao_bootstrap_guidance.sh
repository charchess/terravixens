#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="${root}/terraform/modules/argocd/variables.tf"

grep -Fq 'OpenBao bootstrap input is missing or invalid' "${source_file}"
grep -Fq 'stringData:' "${source_file}"
grep -Fq 'token: <dev-openbao-token>' "${source_file}"
grep -Fq 'outside Git' "${source_file}"
printf 'PASS: OpenBao bootstrap input error is actionable.\n'
