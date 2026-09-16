#!/usr/bin/env bash
# Safe, resumable Talos rollout. Invoked only by Terraform apply.
set -euo pipefail

: "${TALOSCONFIG:?TALOSCONFIG must name a protected talosconfig file}"
: "${KUBECONFIG:?KUBECONFIG must name a protected kubeconfig file}"
: "${TALOS_VERSION:?TALOS_VERSION is required}"
: "${TALOS_IMAGE:?TALOS_IMAGE is required}"
: "${CONTROL_PLANE_NODES:?CONTROL_PLANE_NODES is required}"
: "${WORKER_NODES:?WORKER_NODES is required}"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-10m}"

for command in talosctl kubectl python3; do
  command -v "$command" >/dev/null || { printf 'required command not found: %s\n' "$command" >&2; exit 1; }
done

[[ -r "$TALOSCONFIG" ]] || { printf 'TALOSCONFIG is not readable: %s\n' "$TALOSCONFIG" >&2; exit 1; }
[[ -r "$KUBECONFIG" ]] || { printf 'KUBECONFIG is not readable: %s\n' "$KUBECONFIG" >&2; exit 1; }
[[ "$TALOS_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'invalid TALOS_VERSION: %s\n' "$TALOS_VERSION" >&2; exit 1; }

nodes_from_json() {
  python3 -c '
import json
import sys
nodes = json.load(sys.stdin)
if not isinstance(nodes, list):
    raise SystemExit("node input must be a JSON list")
for node in nodes:
    if not isinstance(node, dict) or not isinstance(node.get("name"), str) or not node["name"] or not isinstance(node.get("ip"), str) or not node["ip"]:
        raise SystemExit("each node requires non-empty string name and ip")
    print("{}\t{}".format(node["name"], node["ip"]))
'
}

control_plane_nodes=$(printf '%s' "$CONTROL_PLANE_NODES" | nodes_from_json)
worker_nodes=$(printf '%s' "$WORKER_NODES" | nodes_from_json)
[[ -n "$control_plane_nodes" ]] || { printf 'CONTROL_PLANE_NODES must not be empty\n' >&2; exit 1; }
if [[ $(printf '%s\n' "$control_plane_nodes" | cut -f1 | sort | uniq -d | wc -l) -ne 0 ]]; then
  printf 'CONTROL_PLANE_NODES contains duplicate node names\n' >&2
  exit 1
fi

server_version() {
  local ip="$1"
  talosctl version --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --short | awk '/^Server:[[:space:]]/ { print $2; exit }'
}

node_is_current() {
  local name="$1" ip="$2" version
  version=$(server_version "$ip")
  [[ -n "$version" ]] || { printf 'could not determine Talos server version for %s (%s)\n' "$name" "$ip" >&2; return 1; }
  if [[ "$version" == "$TALOS_VERSION" ]]; then
    printf 'Talos %s (%s) already at %s; skipping\n' "$name" "$ip" "$TALOS_VERSION"
    return 0
  fi
  printf 'Talos %s (%s) is %s; rollout target is %s\n' "$name" "$ip" "$version" "$TALOS_VERSION"
  return 1
}

upgrade_node() {
  local name="$1" ip="$2"
  printf 'Upgrading Talos %s (%s) to %s\n' "$name" "$ip" "$TALOS_VERSION"
  talosctl upgrade --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --image "$TALOS_IMAGE" --preserve=true --wait=false
}

# A control-plane upgrade is allowed only while every other voter is healthy.
# Evaluated immediately before each node: any failure blocks the next wave.
preflight_control_plane() {
  local target_name="$1" target_ip="$2" peer_name peer_ip
  printf 'preflight:%s\n' "$target_name"
  kubectl --kubeconfig "$KUBECONFIG" get --raw=/readyz >/dev/null
  while IFS=$'\t' read -r peer_name peer_ip; do
    [[ "$peer_name" == "$target_name" ]] && continue
    talosctl health --talosconfig "$TALOSCONFIG" --nodes "$peer_ip" --endpoints "$peer_ip" --wait-timeout "$ROLLOUT_TIMEOUT"
    kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready "node/$peer_name" --timeout="$ROLLOUT_TIMEOUT"
  done <<<"$control_plane_nodes"
  talosctl etcd status --talosconfig "$TALOSCONFIG" --nodes "$target_ip" --endpoints "$target_ip"
}

wait_for_control_plane() {
  local name="$1" ip="$2"
  talosctl health --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --wait-timeout "$ROLLOUT_TIMEOUT"
  kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready "node/$name" --timeout="$ROLLOUT_TIMEOUT"
  talosctl etcd status --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip"
}

wait_for_worker() {
  local name="$1" ip="$2"
  talosctl health --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --wait-timeout "$ROLLOUT_TIMEOUT"
  kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready "node/$name" --timeout="$ROLLOUT_TIMEOUT"
}

while IFS=$'\t' read -r name ip; do
  if node_is_current "$name" "$ip"; then continue; fi
  preflight_control_plane "$name" "$ip"
  upgrade_node "$name" "$ip"
  wait_for_control_plane "$name" "$ip"
done <<<"$control_plane_nodes"

if [[ -n "$worker_nodes" ]]; then
  while IFS=$'\t' read -r name ip; do
    if node_is_current "$name" "$ip"; then continue; fi
    upgrade_node "$name" "$ip"
    wait_for_worker "$name" "$ip"
  done <<<"$worker_nodes"
fi
