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
printf 'Client:\nClient v9.9.9\nServer:\n\tNODE: 192.0.2.19\n\tTag: v1.13.0\n'
MOCK
chmod +x "$tmp/talosctl"
query=$(python3 - "$tmp/talosconfig" <<'PYCODE'
import json,sys
print(json.dumps({'ip':'192.0.2.19','talosconfig':sys.argv[1]}))
PYCODE
)
result=$(printf '%s' "$query" | PATH="$tmp:$PATH" "$script")
python3 - "$result" <<'PYCODE'
import json,sys
assert json.loads(sys.argv[1]) == {'version':'v1.13.0'}
PYCODE
printf 'PASS: observed Talos version emits only JSON version\n'
