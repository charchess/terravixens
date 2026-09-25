#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
main="$root/terraform/modules/talos/main.tf"
# Fresh DHCP/maintenance nodes retain auto bootstrap; installed VLAN nodes stage config.
grep -Fq '\"existing\": \"false\"' "$main"
grep -Fq 'apply_mode                  = data.external.node_endpoint[each.key].result.existing == "true" ? "staged" : "auto"' "$main"
! grep -Fq 'staged_if_needing_reboot' "$main"
echo "PASS: existing nodes stage MachineConfig; fresh nodes retain auto bootstrap"
