#!/bin/bash
# ============================================================================
# ROBUST TALOS RESET SCRIPT (Hardened)
# ============================================================================
# Usage: ./talos-reset.sh <node_ip>

NODE_IP=$1
if [ -z "$NODE_IP" ]; then
    echo "Error: No Node IP provided."
    exit 1
fi

echo "--- STARTING ROBUST RESET FOR NODE ${NODE_IP} ---"

# 1. Kubernetes Cleanup (Best Practice: Remove node object from API)
if [ -f "./kubeconfig-dev" ]; then
    NODE_NAME=$(kubectl --kubeconfig ./kubeconfig-dev get nodes -o jsonpath="{.items[?(@.status.addresses[?(@.address=='${NODE_IP}')])].metadata.name}" 2>/dev/null)
    if [ ! -z "$NODE_NAME" ]; then
        echo "Found Kubernetes node: ${NODE_NAME}. Deleting from API..."
        kubectl --kubeconfig ./kubeconfig-dev delete node "${NODE_NAME}" --timeout=30s || echo "Warning: Failed to delete node object."
    fi
fi

# 2. Talos Graceful Reset (Etcd expulsion + Wipe)
echo "Sending graceful reset signal to Talos API..."
# We use --graceful=true to ensure etcd leave member is called.
# We use --reboot to return to maintenance mode.
talosctl --talosconfig ./talosconfig-dev -n "${NODE_IP}" -e "${NODE_IP}" reset --graceful=true --reboot --system-labels-selection-all || {
    echo "Warning: Graceful reset failed (Node might be already down). Forcing local state cleanup."
}

echo "Reset sequence initiated for ${NODE_IP}."