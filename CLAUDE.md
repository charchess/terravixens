# CLAUDE.md - TerraVixens

This file provides guidance to Claude Code when working with the terravixens repository.

---

## Overview

**TerraVixens** is the infrastructure layer for the Vixens homelab, managing:
- Terraform infrastructure as code
- Talos Linux cluster provisioning
- Cilium CNI deployment
- ArgoCD bootstrap

**GitOps applications:** See [vixens](../vixens) repository (/root/vixens)

---

## Repository Structure

```
terravixens/
├── terraform/
│   ├── modules/           # Reusable Terraform modules
│   │   ├── shared/        # DRY module (single source of truth)
│   │   ├── talos/         # Talos cluster provisioning
│   │   ├── cilium/        # Cilium CNI
│   │   ├── argocd/        # ArgoCD bootstrap
│   │   └── environment/   # Environment orchestration
│   ├── manifests/         # K8s manifests used by Terraform
│   │   ├── argocd/        # ArgoCD root app template
│   │   └── cilium/        # Cilium IP pools and L2 policies
│   ├── base/              # Base configuration
│   └── environments/      # Per-environment configs
│       ├── dev/
│       ├── test/
│       ├── staging/
│       └── prod/
├── docs/                  # Infrastructure documentation
├── scripts/               # Infrastructure scripts
└── .secrets/              # Infisical auth (git-ignored)
```

## Development Workflow

**Infrastructure changes:** terravixens repository  
**Application changes:** vixens repository

---

## Essential Commands

### Terraform Operations

```bash
# Working directory
cd /root/terravixens/terraform/environments/dev

# Standard workflow
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply

# Destroy/recreate (dev/test only!)
terraform destroy -auto-approve
terraform apply -auto-approve
```

**Destroy/Recreate Strategy:**
- Safe for: dev, test (virtualized)
- Dangerous for: staging, prod (physical infrastructure)
- Use when: validating reproducibility, major refactoring
- NOT for: normal development (just apply changes)

### Environment Variables

Each environment requires:
```bash
export KUBECONFIG=/root/terravixens/terraform/environments/dev/kubeconfig-dev
export TALOSCONFIG=/root/terravixens/terraform/environments/dev/talosconfig-dev
```

### Talos Operations

```bash
# Check version
talosctl --nodes 192.168.111.162 --endpoints 192.168.111.162 version

# Check health
talosctl --nodes 192.168.111.162 health

# Check etcd
talosctl --nodes 192.168.111.160 etcd members
```

---

## Infrastructure Stack

- **OS:** Talos Linux v1.11.0 (immutable, API-driven)
- **Kubernetes:** v1.34.0
- **CNI:** Cilium v1.18.3 (eBPF, kube-proxy replacement)
- **GitOps:** ArgoCD v7.7.7 (bootstrapped, then self-managed)
- **LoadBalancer:** Cilium L2 Announcements + LB IPAM
- **Storage:** Synology NAS (192.168.111.69)

---

## Validation

**After infrastructure changes:**
```bash
# Should show "No changes"
terraform -chdir=/root/terravixens/terraform/environments/dev plan

# Check cluster health
kubectl get nodes
kubectl get pods -A
talosctl --nodes 192.168.111.162 health
```

---

## Related Repositories

- **[vixens](/root/vixens)** - GitOps applications (ArgoCD, apps, Kustomize)

---

**Last Updated:** 2026-01-12 (initial creation after repo split)
