#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
rollout="$root/scripts/kubernetes-rollout.sh"
observed="$root/scripts/kubernetes-observed-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
state="$tmp/state"; log="$tmp/log"; config="$tmp/config"
printf test > "$config"; chmod 600 "$config"

cat > "$tmp/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl:%s\n' "$*" >> "$MOCK_LOG"
if [[ "$*" == *'version -o json'* ]]; then
  printf '{"serverVersion":{"gitVersion":"v%s"}}\n' "$(cat "$MOCK_STATE")"
fi
MOCK
cat > "$tmp/bin/talosctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'talosctl:%s\n' "$*" >> "$MOCK_LOG"
if [[ "$1" == 'upgrade-k8s' && "$*" != *'--dry-run'* ]]; then
  target=""; previous=""
  for arg in "$@"; do [[ "$previous" == '--to' ]] && target="$arg"; previous="$arg"; done
  printf '%s' "$target" > "$MOCK_STATE"
fi
MOCK
chmod +x "$tmp/bin/kubectl" "$tmp/bin/talosctl"
export PATH="$tmp/bin:$PATH" MOCK_STATE="$state" MOCK_LOG="$log"
export TALOSCONFIG="$config" KUBECONFIG="$config"
export CONTROL_PLANE_NODES='[{"name":"peach","ip":"10.0.0.1"},{"name":"poison","ip":"10.0.0.2"},{"name":"powder","ip":"10.0.0.3"}]'

printf '1.36.0' > "$state"
result=$(printf '%s' '{"kubeconfig":"'"$config"'"}' | "$observed")
python3 - "$result" <<'PY'
import json, sys
assert json.loads(sys.argv[1]) == {'version': 'v1.36.0'}
PY

export KUBERNETES_VERSION=1.36.0
"$rollout" > "$tmp/noop"
grep -Fq 'already at v1.36.0; skipping' "$tmp/noop"
! grep -Fq 'talosctl:upgrade-k8s' "$log" || { printf 'FAIL: no-op rollout started an upgrade\\n' >&2; exit 1; }

export KUBERNETES_VERSION=1.35.0
if "$rollout" > "$tmp/downgrade" 2>&1; then
  printf 'FAIL: downgrade was accepted\n' >&2; exit 1
fi
grep -Fq 'refusing Kubernetes downgrade' "$tmp/downgrade"

: > "$log"
export KUBERNETES_VERSION=1.37.0
"$rollout" > "$tmp/upgrade"
grep -Fq -- '--dry-run --manifests-no-prune' "$log"
grep -Fq -- '--manifests-no-prune' "$log"
grep -Fq 'upgrade-k8s' "$log"
[[ "$(cat "$state")" == '1.37.0' ]] || { printf 'FAIL: target version was not observed after mock upgrade\n' >&2; exit 1; }
grep -Fq 'Kubernetes rollout verified at v1.37.0' "$tmp/upgrade"
printf 'PASS: Kubernetes rollout is opt-in, monotonic, preflighted, and no-prune\n'
