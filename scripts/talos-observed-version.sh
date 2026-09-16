#!/usr/bin/env bash
set -euo pipefail
query=$(cat)
readarray -t values < <(printf '%s' "$query" | python3 -c '
import json,sys
q=json.load(sys.stdin)
ip=q.get("ip", ""); talosconfig=q.get("talosconfig", "")
if not isinstance(ip,str) or not ip or not isinstance(talosconfig,str) or not talosconfig: raise SystemExit("ip and talosconfig are required")
print(ip); print(talosconfig)
')
ip="${values[0]}"; talosconfig="${values[1]}"
[[ -r "$talosconfig" ]] || { printf 'talosconfig is unreadable\n' >&2; exit 1; }
version=$(talosctl version --talosconfig "$talosconfig" --nodes "$ip" --endpoints "$ip" --short | awk '/^Server:[[:space:]]/ { print $2; exit }')
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'unable to obtain Talos server version\n' >&2; exit 1; }
printf '{"version":"%s"}\n' "$version"
