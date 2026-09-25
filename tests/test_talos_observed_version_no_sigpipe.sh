#!/usr/bin/env bash
# Contract: parsing a long Talos --short response must not terminate talosctl with SIGPIPE under pipefail.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/talosconfig"
cat >"$tmp/talosctl" <<'FAKE'
#!/usr/bin/env bash
printf 'Client:\nClient v1.6.7\nServer:\n\tNODE: 192.168.111.191\n\tTag: v1.14.1\n'
# Simulate the rest of a real response; an early reader closes the pipe and yields SIGPIPE.
for i in $(seq 1 4000); do printf 'padding-%s\n' "$i"; done
FAKE
chmod 755 "$tmp/talosctl"
actual=$(printf '{"ip":"192.168.111.191","talosconfig":"%s"}' "$tmp/talosconfig" | PATH="$tmp:$PATH" "$ROOT/scripts/talos-observed-version.sh")
[[ "$actual" == '{"version":"v1.14.1"}' ]]
echo "PASS: observed-version parser consumes long Talos output without SIGPIPE"
