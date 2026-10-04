#!/usr/bin/env bash
# Explicitly gated, monotonic Kubernetes rollout. Invoked only by Terraform apply.
set -euo pipefail

: "${TALOSCONFIG:?TALOSCONFIG must name a protected talosconfig file}"
: "${KUBECONFIG:?KUBECONFIG must name a protected kubeconfig file}"
: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"
: "${CONTROL_PLANE_NODES:?CONTROL_PLANE_NODES is required}"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-10m}"

for command in talosctl kubectl python3; do
  command -v "$command" >/dev/null || { printf 'required command not found: %s\n' "$command" >&2; exit 1; }
done
[[ -r "$TALOSCONFIG" ]] || { printf 'TALOSCONFIG is not readable: %s\n' "$TALOSCONFIG" >&2; exit 1; }
[[ -r "$KUBECONFIG" ]] || { printf 'KUBECONFIG is not readable: %s\n' "$KUBECONFIG" >&2; exit 1; }

normalize_version() {
  local version="${1#v}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'invalid Kubernetes version: %s\n' "$1" >&2; return 1; }
  printf '%s\n' "$version"
}

version_cmp() {
  python3 - "$1" "$2" <<'PY'
import sys
left = tuple(map(int, sys.argv[1].split(".")))
right = tuple(map(int, sys.argv[2].split(".")))
print((left > right) - (left < right))
PY
}

control_plane_nodes=$(printf '%s' "$CONTROL_PLANE_NODES" | python3 -c '
import json, sys
nodes = json.load(sys.stdin)
if not isinstance(nodes, list) or not nodes:
    raise SystemExit("CONTROL_PLANE_NODES must be a non-empty JSON list")
seen = set()
for node in nodes:
    if not isinstance(node, dict) or not isinstance(node.get("name"), str) or not node["name"] or not isinstance(node.get("ip"), str) or not node["ip"]:
        raise SystemExit("each control-plane node requires non-empty string name and ip")
    if node["name"] in seen:
        raise SystemExit("CONTROL_PLANE_NODES contains duplicate node names")
    seen.add(node["name"])
    print("{}\t{}".format(node["name"], node["ip"]))
')

target=$(normalize_version "$KUBERNETES_VERSION")
live=$(kubectl --kubeconfig "$KUBECONFIG" version -o json | python3 -c '
import json, sys
version = json.load(sys.stdin).get("serverVersion", {}).get("gitVersion", "")
if not isinstance(version, str):
    raise SystemExit("Kubernetes server version is invalid")
print(version)
')
live=$(normalize_version "$live")
comparison=$(version_cmp "$target" "$live")

if [[ "$comparison" == 0 ]]; then
  printf 'Kubernetes already at v%s; skipping\n' "$target"
  exit 0
fi
if [[ "$comparison" -lt 0 ]]; then
  printf 'refusing Kubernetes downgrade: live v%s is newer than declared v%s\n' "$live" "$target" >&2
  exit 1
fi

kubectl --kubeconfig "$KUBECONFIG" get --raw=/readyz >/dev/null
while IFS=$'\t' read -r name ip; do
  talosctl health --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --wait-timeout "$ROLLOUT_TIMEOUT"
  kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready "node/$name" --timeout="$ROLLOUT_TIMEOUT"
done <<<"$control_plane_nodes"

first_ip=$(printf '%s\n' "$control_plane_nodes" | head -n1 | cut -f2)
printf 'Preflighting Kubernetes v%s -> v%s with bootstrap-manifest pruning disabled\n' "$live" "$target"
talosctl upgrade-k8s --talosconfig "$TALOSCONFIG" --nodes "$first_ip" --endpoints "$first_ip" --from "$live" --to "$target" --dry-run --manifests-no-prune
printf 'Upgrading Kubernetes v%s -> v%s with bootstrap-manifest pruning disabled\n' "$live" "$target"
talosctl upgrade-k8s --talosconfig "$TALOSCONFIG" --nodes "$first_ip" --endpoints "$first_ip" --from "$live" --to "$target" --manifests-no-prune

kubectl --kubeconfig "$KUBECONFIG" get --raw=/readyz >/dev/null
while IFS=$'\t' read -r name ip; do
  talosctl health --talosconfig "$TALOSCONFIG" --nodes "$ip" --endpoints "$ip" --wait-timeout "$ROLLOUT_TIMEOUT"
  kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready "node/$name" --timeout="$ROLLOUT_TIMEOUT"
done <<<"$control_plane_nodes"

observed=$(kubectl --kubeconfig "$KUBECONFIG" version -o json | python3 -c 'import json, sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')
[[ "$(normalize_version "$observed")" == "$target" ]] || { printf 'Kubernetes version did not converge to v%s\n' "$target" >&2; exit 1; }
printf 'Kubernetes rollout verified at v%s\n' "$target"
