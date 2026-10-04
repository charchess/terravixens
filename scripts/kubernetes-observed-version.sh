#!/usr/bin/env bash
set -euo pipefail

query=$(cat)
readarray -t values < <(printf '%s' "$query" | python3 -c '
import json, sys
q = json.load(sys.stdin)
kubeconfig = q.get("kubeconfig", "")
if not isinstance(kubeconfig, str) or not kubeconfig:
    raise SystemExit("kubeconfig is required")
print(kubeconfig)
')

kubeconfig="${values[0]}"
[[ -r "$kubeconfig" ]] || { printf 'kubeconfig is unreadable\n' >&2; exit 1; }

version=$(kubectl --kubeconfig "$kubeconfig" version -o json | python3 -c '
import json, sys
version = json.load(sys.stdin).get("serverVersion", {}).get("gitVersion", "")
if not isinstance(version, str):
    raise SystemExit("Kubernetes server version is invalid")
print(version)
')

[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'unable to obtain Kubernetes server version\n' >&2; exit 1; }
printf '{"version":"%s"}\n' "$version"
