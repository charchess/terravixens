# Testing Matrix & Validation Status

This document tracks which deployment scenarios have been tested and validated, and which remain untested.

## Test Environment

- **Date:** 2026-03-03
- **Talos Version:** v1.12.4
- **Kubernetes Version:** v1.34.0
- **ArgoCD Version:** v3.3.0
- **Cilium Version:** Latest (via Helm)

---

## ✅ Tested Scenarios

### Cluster Lifecycle

| Scenario | Environment | Status | Notes |
|----------|-------------|--------|-------|
| **0 → 1 CP (single node)** | dev (daphne) | ✅ PASS | 15m 26s total, cluster fully operational |
| **Destroy (1 CP)** | dev | ⚠️ PARTIAL | Terraform destroy works, but manual node reset required (talosconfig destroyed before reset script runs) |
| **Migration Helm → kubectl** | prod (5 nodes) | ✅ PASS | Clean migration, 1m 22s downtime, 93 apps preserved |

### Component Installation

| Component | Environment | Status | Notes |
|-----------|-------------|--------|-------|
| **Talos bootstrap** | dev, prod | ✅ PASS | Boots from maintenance mode successfully |
| **Cilium CNI** | dev, prod | ✅ PASS | Nodes reach Ready state after CNI install |
| **Cilium L2 LoadBalancer** | dev, prod | ✅ PASS | IP assignment working (after interface fix) |
| **ArgoCD bootstrap (kubectl)** | dev, prod | ✅ PASS | 59 manifests applied successfully |
| **ArgoCD self-heal** | prod | ✅ PASS | Survived migration, picked up GitOps state |
| **Anonymous admin access** | dev, prod | ✅ PASS | ConfigMaps auto-created, no-auth working |

### Configuration Changes

| Change | Environment | Status | Notes |
|--------|-------------|--------|-------|
| **LoadBalancer IP template** | dev, prod | ✅ PASS | IPs correctly injected from tfvars |
| **L2 interface correction** | dev, prod | ✅ PASS | `eth1` → `enx0ed514c.208` applied |
| **Talos upgrade provisioner timeout** | dev | ✅ PASS | Prevents infinite loops during bootstrap |

---

## ❌ Untested Scenarios

### Multi-Node Cluster Patterns

| Scenario | Risk Level | Impact |
|----------|------------|--------|
| **0 → 3 CP (HA bootstrap)** | 🟡 MEDIUM | Sequential CP bootstrap with `wait_for_previous` untested |
| **1 CP → 3 CP (scale-up control plane)** | 🟡 MEDIUM | Etcd quorum migration path not validated |
| **3 CP → 1 CP (scale-down)** | 🔴 HIGH | Etcd data loss potential, graceful degradation unknown |
| **1 CP + 0 W → 1 CP + 1 W (add worker)** | 🟢 LOW | Should work but not verified |
| **1 CP + 1 W → 1 CP + 0 W (remove worker)** | 🟢 LOW | Worker removal straightforward but untested |
| **3 CP + 3 W → full cluster** | 🟡 MEDIUM | Large-scale bootstrap timing unknown |

### Destroy Patterns

| Scenario | Risk Level | Impact |
|----------|------------|--------|
| **Full destroy (multi-node)** | 🔴 HIGH | Unknown if all nodes reset correctly |
| **Partial destroy (remove 1 node)** | 🔴 HIGH | State consistency untested |
| **Destroy with failed nodes** | 🔴 HIGH | Error handling unknown |
| **Destroy → Apply (full cycle)** | 🟡 MEDIUM | **Manual node reset required** - automated reset fails due to talosconfig lifecycle |

### Edge Cases

| Scenario | Risk Level | Impact |
|----------|------------|--------|
| **Network interruption during bootstrap** | 🔴 HIGH | Timeout behavior not validated |
| **Node reboot during apply** | 🔴 HIGH | State recovery unknown |
| **Concurrent applies (race condition)** | 🔴 HIGH | Locking mechanism untested |
| **Apply with existing stale resources** | 🟡 MEDIUM | Cleanup behavior not verified |
| **Version upgrades (Talos/K8s/ArgoCD)** | 🔴 HIGH | In-place upgrade path untested |

### GitOps Scenarios

| Scenario | Risk Level | Impact |
|----------|------------|--------|
| **ArgoCD bootstrap conflict with GitOps** | 🟢 LOW | `lifecycle { ignore_changes = all }` should prevent, but not tested at scale |
| **GitOps override of Terraform-managed resources** | 🟡 MEDIUM | Ownership boundaries not stress-tested |
| **Tag promotion (dev → staging → prod-stable)** | 🟡 MEDIUM | Workflow exists but multi-env sync untested |

---

## 🐛 Known Issues

### Critical

1. **Destroy doesn't auto-reset nodes to maintenance mode**
   - **Cause:** `talosconfig` destroyed before `node_reset_on_destroy` provisioner runs
   - **Impact:** Manual intervention required between destroy/apply cycles
   - **Workaround:** Manually reset nodes to maintenance mode before `terraform apply`
   - **Fix Required:** Preserve talosconfig for destroy provisioner or use alternative reset method

### Medium

2. **Initial LoadBalancer IP mismatch**
   - **Cause:** Bootstrap manifest had hardcoded dev IP (192.168.208.71)
   - **Impact:** Prod clusters got wrong IP initially, required manual patch
   - **Status:** ✅ FIXED (templated service with environment-specific IP)
   - **Residual Risk:** Existing clusters may have mismatched IPs until next apply

3. **Cilium L2 interface name assumption**
   - **Cause:** Assumed `eth1` instead of actual Talos VLAN interface name
   - **Impact:** LoadBalancer IPs not announced, services stuck in `<pending>`
   - **Status:** ✅ FIXED (updated tfvars to use `enx0ed514c.208`)
   - **Residual Risk:** New environments must verify actual interface name

### Low

4. **wait-for-k8s-api script has long initial delay**
   - **Cause:** `INITIAL_DELAY=90s` too conservative for fast Talos boots
   - **Impact:** +26s beyond 15min target for apply
   - **Status:** 🔧 OPTIMIZATION OPPORTUNITY (reduce to 30-40s could save ~60s)

---

## 🎯 Recommended Testing Priorities

### High Priority (Before Production Scale-Out)

1. **3 CP bootstrap from scratch** - Validate HA cluster creation
2. **Full destroy/apply cycle** - Fix automated node reset or document manual steps
3. **Version upgrade path** - Test Talos/K8s version changes without destroy

### Medium Priority (Before Multi-Environment Rollout)

4. **Scale-up control plane (1→3 CP)** - Validate etcd expansion
5. **Worker node add/remove** - Validate worker lifecycle
6. **Network resilience testing** - Validate timeout/retry logic

### Low Priority (Nice to Have)

7. **Concurrent apply protection** - Add state locking if needed
8. **Optimize wait timings** - Reduce bootstrap time
9. **Staging environment validation** - Test full dev→staging→prod flow

---

## 📝 Testing Methodology

When testing new scenarios, document:

1. **Initial state** - Cluster topology, Terraform state
2. **Command executed** - Exact `terraform` command with flags
3. **Duration** - Total time and breakdown by phase
4. **Outcome** - Success/failure with error messages
5. **Manual interventions** - Any required human actions
6. **Validation** - How you verified the result
7. **Rollback procedure** - How to undo if needed

**Example:**
```bash
# Scenario: 1 CP → 3 CP scale-up
# Initial: 1 CP (daphne), Terraform state clean
# Command: terraform apply -auto-approve
# Duration: 12m 30s (Talos: 8m, K8s: 3m, Cilium: 1m 30s)
# Outcome: ✅ SUCCESS - All 3 CP nodes joined, etcd quorum established
# Manual: None
# Validation: kubectl get nodes (3 Ready), etcdctl member list (3 members)
# Rollback: terraform destroy, reset nodes to maintenance
```

---

## 🔄 Update History

- **2026-03-03** - Initial documentation after dev/prod migration validation
- Document created by Claude during Helm → kubectl ArgoCD migration project

---

## 📚 Related Documentation

- **AGENTS.md** - Agent instructions for issue tracking with `bd`
- **README.md** - Project overview and getting started (if exists)
- Main Terraform code: `terraform/modules/` and `terraform/environments/`

---

**Note:** This is a living document. Update this file whenever new scenarios are tested or issues discovered.
