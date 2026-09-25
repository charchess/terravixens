#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
main="$root/terraform/modules/talos/main.tf"
# Fresh DHCP/maintenance nodes retain auto bootstrap; installed VLAN nodes stage config.
grep -Fq '\"existing\": \"false\"' "$main"
grep -Fq 'data.external.node_endpoint[k].result.existing == "true" ? {} : { hostname = v.name }' "$main"
grep -Fq 'apply_mode                  = data.external.node_endpoint[each.key].result.existing == "true" ? "staged_if_needing_reboot" : "auto"' "$main"
grep -Fq 'staged_if_needing_reboot' "$main"
echo "PASS: existing nodes use provider-managed staged-or-auto apply; fresh nodes retain auto bootstrap"
