#!/bin/bash
# ============================================================================
# AUTOMATIC KUBERNETES CSR APPROVER (V2 - Hardened)
# ============================================================================
KUBECONFIG_PATH=$1
TIMEOUT=${2:-300}

echo "[$(date +%T)] INFO: Starting Auto-CSR Approver for ${TIMEOUT}s..."

START_TIME=$(date +%s)
while [ $(( $(date +%s) - START_TIME )) -lt $TIMEOUT ]; do
    # On cherche les CSR Pending
    PENDING_CSRS=$(kubectl --kubeconfig "${KUBECONFIG_PATH}" get csr 2>/dev/null | grep "Pending" | awk '{print $1}')
    
    if [ ! -z "$PENDING_CSRS" ]; then
        for csr in $PENDING_CSRS; do
            echo "[$(date +%T)] ACTION: Approving CSR: $csr"
            kubectl --kubeconfig "${KUBECONFIG_PATH}" certificate approve "$csr" 2>/dev/null
        done
    fi
    sleep 5
done
echo "[$(date +%T)] INFO: Auto-CSR Approver finished."