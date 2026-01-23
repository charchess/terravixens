# TerraVixens - Infrastructure as Code

**TerraVixens** is the infrastructure layer for the Vixens homelab, utilizing Terraform to provision immutable Talos Linux clusters, Cilium for networking, and ArgoCD for GitOps bootstrapping.

## Project Overview

*   **Type:** Infrastructure as Code (IaC)
*   **Primary Tool:** Terraform
*   **Operating System:** Talos Linux (Immutable Kubernetes OS)
*   **Networking:** Cilium (eBPF-based)
*   **GitOps:** ArgoCD (Bootstrapped here, manages apps from the [vixens](https://github.com/charchess/vixens) repo)

## Infrastructure Stack

*   **OS:** Talos Linux v1.11.0
*   **Kubernetes:** v1.34.0
*   **CNI:** Cilium v1.18.3 (kube-proxy replacement, L2 Announcements)
*   **GitOps:** ArgoCD v7.7.7
*   **Storage:** Synology NAS (NFS/iSCSI)

## Directory Structure

*   `terraform/modules/`: Reusable Terraform modules (Talos, Cilium, ArgoCD, Shared).
*   `terraform/base/`: Base configuration.
*   `terraform/environments/`: Environment-specific configurations.
    *   `dev/`: Development cluster (nodes: obsy, onyx, opale).
    *   `test/`: Test cluster (nodes: citrine, carny, celesty).
    *   `staging/`: Staging cluster.
    *   `prod/`: Production cluster (Physical nodes).
*   `manifests/`: Kubernetes manifests (e.g., Cilium policies, ArgoCD root app).
*   `docs/`: Detailed infrastructure documentation.

## Workflows

### 1. Infrastructure Deployment (Terraform)

Navigate to the specific environment directory before running commands:

```bash
cd terraform/environments/<env>  # e.g., dev, test
```

Set up environment variables (if not using direnv):

```bash
export KUBECONFIG=$(pwd)/kubeconfig-<env>
export TALOSCONFIG=$(pwd)/talosconfig-<env>
```

Standard Terraform Lifecycle:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

### 2. Issue Tracking (Beads)

This project uses **bd** (beads) for task management.

*   `bd ready`: Find available work.
*   `bd update <id> --status in_progress`: Start working on an issue.
*   `bd close <id>`: Mark an issue as complete.
*   `bd sync`: Sync issues with the git repository.

### 3. Session Completion (Mandatory)

**Work is NOT complete until it is pushed to the remote.**

1.  **File Issues:** Create `bd` issues for any remaining work.
2.  **Update Status:** Close completed `bd` issues.
3.  **Push:**
    ```bash
    git pull --rebase
    bd sync
    git push
    ```
4.  **Verify:** Ensure `git status` is clean and up to date.

## Key Configuration Details

*   **VLANs:** Internal and Services VLANs are distinct per environment.
*   **VIPs:** Each environment has a unique Control Plane VIP.
*   **State:** Terraform state is managed independently for each environment.
