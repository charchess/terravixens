# TerraVixens Cluster Lifecycle Stories

This document defines the operational scenarios that the TerraVixens infrastructure must support reliably, with a focus on preventing accidental data loss or cluster resets.

## CRITICAL CONSTRAINT
**Non-Destructive Operations Side Effects:** Adding a node, upgrading a version, or modifying non-essential metadata must NEVER trigger a cluster reset or re-bootstrap of existing healthy nodes.

---

## 1. Node Management

### 1.1 Add/Remove Worker Node
*   **Goal:** Scale the cluster's compute capacity.
*   **Technical Impact:** Update `worker_nodes` map in `terraform.tfvars`.
*   **Risk:** Ensure `null_resource.worker_reset_on_destroy` only triggers for the specific node being removed, not the entire worker set.

### 1.2 Add/Remove Control Plane Node
*   **Goal:** Change control plane capacity (e.g., 1 -> 3 or 3 -> 5).
*   **Constraint:** Maintain etcd quorum (odd number of nodes).
*   **Validation:** Terraform variable validation must enforce `count % 2 == 1`.
*   **Risk:** Talos/Etcd requires specific "join" or "remove" procedures. Modifying the set in Terraform must not confuse the existing members' view of the cluster.

### 1.3 Node Reconfiguration (IP, Hostname)
*   **Goal:** Change networking or naming without redeploying hardware.
*   **Risk:** Changing an IP in Terraform usually triggers a `Destroy -> Create` cycle. In the current implementation, `Destroy` triggers a `talosctl reset`, which is **unacceptable** for simple renames or IP migrations.

---

## 2. Maintenance & Upgrades

### 2.1 OS Upgrade (Talos)
*   **Goal:** Update Talos Linux version across the cluster.
*   **Technical Impact:** Update `talos_version` or `talos_image` in `tfvars`.
*   **Requirement:** Sequential upgrade (one node at a time) to maintain availability.
*   **Risk:** The current `local-exec` upgrade trigger must be robust and wait for node readiness before proceeding to the next.

### 2.2 Kubernetes Upgrade
*   **Goal:** Update K8s version.
*   **Requirement:** Triggered via Talos configuration update.
*   **Risk:** Ensure API compatibility during the transition.

---

## 3. Full Lifecycle

### 3.1 New Cluster Provisioning
*   **Goal:** Bootstrap a new cluster from scratch (Maintenance mode nodes).
*   **Requirement:** Zero-touch provisioning until ArgoCD is ready.

### 3.2 Cluster Decommissioning
*   **Goal:** Wipe all nodes and destroy Terraform state.
*   **Requirement:** `terraform destroy` must successfully reset all nodes to Maintenance mode.

---

## 4. Safety Audit Needed
- [ ] Review `null_resource` triggers for upgrades and resets.
- [ ] Evaluate `talos_machine_configuration_apply` behavior on non-critical field changes.
- [ ] Test "Add Node" scenario in `dev` to ensure zero impact on existing nodes.
