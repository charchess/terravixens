#!/usr/bin/env bash
# Contract: existing nodes use node_endpoint (VLAN 111); fresh nodes use delivery IP only at create time.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FILE="$ROOT/terraform/modules/talos/main.tf"
python3 - "$FILE" <<'PYCODE'
import sys
text=open(sys.argv[1]).read()
for name in ('control_plane','worker'):
 start=text.index(f'resource "talos_machine_configuration_apply" "{name}" {{')
 end=text.index('\n}',start)+2; block=text[start:end]
 if block.count(f'data.external.node_endpoint[each.key].result.ip') != 2:
  raise SystemExit(f'FAIL: {name} configuration apply does not use the endpoint resolver for node and endpoint')
start=text.index('data "external" "node_endpoint" {')
end=text.index('\n}',start)+2; resolver=text[start:end]
if 'VLAN_IP=' not in resolver or 'existing\\": \\"true' not in resolver:
 raise SystemExit('FAIL: endpoint resolver does not retain final VLAN 111 path for existing nodes')
for resource in ('talos_machine_bootstrap','talos_cluster_kubeconfig'):
 start=text.index(f'resource "{resource}" "this" {{')
 end=text.index('\n}',start)+2; block=text[start:end]
 if 'ignore_changes = [node, endpoint]' not in block:
  raise SystemExit(f'FAIL: {resource} does not preserve its historical bootstrap endpoint')
print('PASS: Talos state addressing uses resolver; bootstrap endpoints remain preserved')
PYCODE
