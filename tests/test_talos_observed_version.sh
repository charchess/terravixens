#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/talos-observed-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf test > "$tmp/talosconfig"; chmod 600 "$tmp/talosconfig"
cat > "$tmp/talosctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'Client: v9.9.9\nServer: v1.13.0\n'
MOCK
chmod +x "$tmp/talosctl"
query=$(python3 - "$tmp/talosconfig" <<'PY'
import json,sys
print(json.dumps({'ip':'192.0.2.19','talosconfig':sys.argv[1]}))
PY
)
result=$(printf '%s' "$query" | PATH="$tmp:$PATH" "$script")
python3 - "$result" <<'PY'
import json,sys
assert json.loads(sys.argv[1]) == {'version':'v1.13.0'}
PY
printf 'PASS: observed Talos version emits only JSON version\n'
