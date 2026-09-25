#!/usr/bin/env bash
set -euo pipefail
extract() { awk '/^[[:space:]]*Tag:[[:space:]]/ { print $2; exit }'; }
actual=$(printf 'Client:
Client v1.6.7
Server:
	NODE: 192.168.111.191
	Tag: v1.14.1
' | extract)
[[ "$actual" == "v1.14.1" ]]
[[ -z "$(printf 'Server: v1.14.1
' | extract)" ]]
echo "PASS: Talos version parser accepts current --short Tag output only"
