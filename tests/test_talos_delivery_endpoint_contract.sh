#!/usr/bin/env bash
# Contract: a fresh Talos node is reached through delivery_ip, never its final VLAN 111 IP.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT/terraform/modules/talos/variables.tf" "$ROOT/terraform/modules/talos/main.tf" <<'PY2'
import sys
variables, main = (open(p).read() for p in sys.argv[1:])
if 'delivery_ip  = string' not in variables:
    raise SystemExit('FAIL: Talos nodes do not declare a dedicated delivery_ip')
start=main.index('data "external" "node_endpoint" {')
end=main.index('\n}', start)+2
block=main[start:end]
if 'DELIVERY_IP="${each.value.delivery_ip}"' not in block:
    raise SystemExit('FAIL: endpoint resolver does not receive delivery_ip')
if '$DELIVERY_IP' not in block:
    raise SystemExit('FAIL: fresh node fallback does not use delivery_ip')
if 'MAINTENANCE_IP="${each.value.ip_address}"' in block:
    raise SystemExit('FAIL: final management IP is still masquerading as maintenance IP')
print('PASS: fresh nodes use separate delivery IPs; existing nodes use final VLAN 111')
PY2
