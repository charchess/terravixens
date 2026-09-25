#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
main="$root/terraform/modules/talos/main.tf"
grep -Fq 'result.existing == "true" ? "staged_if_needing_reboot" : "auto"' "$main"
grep -Fq 'kind = "HostnameConfig"' "$main"
grep -Fq 'hostname = v.name' "$main"
grep -Fq 'auto = "off"' "$main"
! grep -Fq 'network = merge(
          data.external.node_endpoint' "$main"
echo "PASS: HostnameConfig is explicit; existing nodes use staged-or-auto apply"
