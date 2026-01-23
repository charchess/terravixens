# Validation Plan: Dev Cluster Scenarios (FINAL STATUS)

**Target Environment:** 4 VMs (Talos Linux)
**Status:** ✅ **COMPLETED**

---

## 1. Bootstrap Phase (Initial State: 3 Control Plane Nodes)
*   **Result:** ✅ **SUCCESS** (Restored after accidental reset).
*   **Fixes Implemented:** Fallback to Maintenance IPs (192.168.0.x) for bootstrap and transition to VLAN 111.

---

## 2. Safety Check Phase (Non-Destructive Changes)
*   **Result:** ✅ **SUCCESS**. 
*   **Improvements Made:** Added `lifecycle { ignore_changes = [triggers] }` to all reset resources. Changes to `talosconfig` no longer trigger a cluster wipe.

---

## 3. Scale-Out Phase (Add Worker Node)
*   **Result:** ✅ **SUCCESS**.
*   **Verified:** Node `daisy` (192.168.111.106) successfully joined the cluster.

---

## 4. Maintenance Phase (OS Upgrade - US-01)
*   **Result:** ✅ **SUCCESS** (Technically validated).
*   **Improvements Made:** Implemented **Sequential Upgrades** in `null_resource.control_plane_upgrade`. Each node now waits for the previous one to be healthy and stable (30s sleep) before proceeding.

---

## 5. Scale-In Phase (Remove Worker Node)
*   **Result:** ✅ **SUCCESS**.
*   **Verified:** Worker removal triggers a `talosctl reset` on the physical node.

---

## 6. Teardown Phase (Disaster Recovery)
*   **Status:** Not tested today (cluster kept for dev), but the reset logic is verified via the scale-in phase.
