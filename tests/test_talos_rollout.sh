#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/talos-rollout.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
state="$tmp/upgraded"; log="$tmp/log"; talosconfig="$tmp/talosconfig"
printf test > "$talosconfig"; chmod 600 "$talosconfig"
cat > "$tmp/bin/talosctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
node=""; previous=""
for arg in "$@"; do [[ "$previous" == "--nodes" ]] && node="$arg"; previous="$arg"; done
case "$1" in
 version)
   if grep -qx "$node" "$MOCK_STATE" 2>/dev/null || [[ "$node" == "10.0.0.1" ]]; then v=v1.2.3; else v=v1.1.0; fi
   printf 'Client:\nTalos v9.9.9\nServer:\n\tNODE: %s\n\tTag: %s\n' "$node" "$v" ;;
 upgrade) printf 'upgrade:%s\n' "$node" >> "$MOCK_LOG"; printf '%s\n' "$node" >> "$MOCK_STATE" ;;
 health) printf 'health:%s\n' "$node" >> "$MOCK_LOG" ;;
 etcd) printf 'etcd:%s\n' "$node" >> "$MOCK_LOG" ;;
 *) printf 'unexpected talosctl: %s\n' "$*" >&2; exit 2 ;;
esac
MOCK
cat > "$tmp/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl:%s\n' "$*" >> "$MOCK_LOG"
MOCK
chmod +x "$tmp/bin/talosctl" "$tmp/bin/kubectl"
export PATH="$tmp/bin:$PATH" MOCK_STATE="$state" MOCK_LOG="$log"
export TALOSCONFIG="$talosconfig" KUBECONFIG="$talosconfig" TALOS_VERSION=v1.2.3 TALOS_IMAGE=example.invalid/installer:v1.2.3
export CONTROL_PLANE_NODES='[{"name":"peach","ip":"10.0.0.1"},{"name":"poison","ip":"10.0.0.2"},{"name":"powder","ip":"10.0.0.3"}]'
export WORKER_NODES='[]' ROLLOUT_TIMEOUT=1s
runout="$tmp/rollout.out"
"$script" > "$runout"
line_count() { grep -c "$1" "$log" || true; }
line_join() { grep "$1" "$log" | paste -sd, -; }
assert_eq "$(line_join '^upgrade:')" 'upgrade:10.0.0.2,upgrade:10.0.0.3'
assert_eq "$(line_count '^health:')" 6
assert_eq "$(line_count '^etcd:')" 4
assert_eq "$(line_count 'kubectl:.* wait ')" 6
grep -Fq 'server && /^[[:space:]]*Tag:' "$script" || fail 'server version parser does not select Server Tag'
grep -Fq 'health_with_retry' "$script" || fail 'postflight retry helper missing'
# RED requirement: each pending node needs an all-peer preflight first.
assert_eq "$(grep -c '^preflight:' "$runout")" 2
assert_eq "$(grep '^preflight:' "$runout" | paste -sd, -)" 'preflight:poison,preflight:powder'
"$script"
assert_eq "$(line_count '^upgrade:')" 2
export CONTROL_PLANE_NODES='[{"name":"peach","ip":"10.0.0.1"},{"name":"peach","ip":"10.0.0.3"}]'
if "$script" >/dev/null 2>&1; then fail 'expected duplicate-name validation failure'; fi
# Legacy state must remain tracked until explicitly retired, but must never reset a node.
module_source="$repo_root/terraform/modules/talos/main.tf"
grep -q 'resource "null_resource" "node_reset_on_destroy"' "$module_source" || fail 'legacy reset state holder missing'
grep -q 'talosconfig = data.talos_client_configuration.this.talos_config' "$module_source" || fail 'legacy reset state trigger compatibility missing'
if grep -Eq 'when[[:space:]]*=[[:space:]]*destroy|talos-reset\.sh' "$module_source"; then
  fail 'destroy-triggered Talos reset remains in module'
fi
printf 'PASS: Talos rollout ordering, cross-node preflight, readiness, and resume behavior\n'
