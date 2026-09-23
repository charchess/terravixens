#!/usr/bin/env bash
# Contract: existing prod Talos state uses management IPs; bootstrap endpoints are create-time only.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FILE="$ROOT/terraform/modules/talos/main.tf"
python3 - "$FILE" <<'PY'
import sys
text=open(sys.argv[1]).read()
for name in ('control_plane','worker'):
 start=text.index(f'resource "talos_machine_configuration_apply" "{name}" {{')
 end=text.index('\n}',start)+2; block=text[start:end]
 if block.count('each.value.ip_address') < 2:
  raise SystemExit(f'FAIL: {name} configuration apply is not pinned to declared management IP')
for name in ('this',):
 for resource in ('talos_machine_bootstrap','talos_cluster_kubeconfig'):
  start=text.index(f'resource "{resource}" "{name}" {{')
  end=text.index('\n}',start)+2; block=text[start:end]
  if 'ignore_changes = [node, endpoint]' not in block:
   raise SystemExit(f'FAIL: {resource} does not preserve its historical bootstrap endpoint')
print('PASS: Talos state addressing contract')
PY
