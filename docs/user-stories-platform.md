# User Stories: TerraVixens Platform Lifecycle

These user stories define the required behavior of the TerraVixens Terraform codebase to ensure operational stability and prevent accidental data loss.

---

## 1. Upgrade & Maintenance

### US-01: Sequential Upgrades (Anti-Split-Brain)
**As an operator,** I want Terraform to upgrade Control Plane nodes one-by-one, waiting for the current node to be healthy before starting the next, **so that** the etcd quorum is never lost.
*   **Validation:** Running a version upgrade must show sequential execution in the logs.
*   **Risk:** Parallel upgrades trigger a cluster-wide failure (Split-brain).

### US-02: Non-Destructive Metadata Updates
**As an operator,** I want to modify non-critical metadata (e.g., tags, resource names, local file paths) **so that** existing healthy nodes are never reset or rebooted by accident.
*   **Validation:** Changing `pool_name` or `talosconfig` path should not trigger a `talosctl reset`.
*   **Technical Implementation:** Use `lifecycle { ignore_changes = [triggers] }` on all destructive `null_resource` blocks.

---

## 2. Provisioning & Networking

### US-03: Multi-Network Bootstrap (Maintenance Fallback)
**As an operator,** I want the provisioning process to automatically detect if a node is in "Maintenance Mode" (192.168.0.x) or "Configured Mode" (VLAN IPs), **so that** bootstrapping works from any state without manual IP switching.
*   **Validation:** Running `terraform apply` on a reset node successfully pushes the configuration via the maintenance IP and transitions to VLAN IPs.

### US-04: Single Source of Truth (Dynamic Config)
**As an operator,** I want to manage all cluster parameters (Talos, Cilium L2, ArgoCD) exclusively via `terraform.tfvars` **so that** there is no configuration drift between Terraform and static YAML manifests.
*   **Validation:** Changing an IP range in `tfvars` correctly updates the `CiliumLoadBalancerIPPool` manifest.

---

## 3. GitOps Integration

### US-05: Neutral Handoff (Safety Mode)
**As an operator,** I want to be able to bootstrap ArgoCD without triggering the deployment of the full application stack **so that** I can validate the infrastructure platform independently.
*   **Validation:** Setting `git_branch` to a non-existent branch allows ArgoCD to install but stay in a "clean" state.
