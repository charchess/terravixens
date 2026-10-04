# Kubernetes upgrade ownership boundary

## Current contract

`Terraform apply` may reconcile Talos MachineConfig and Talos OS versions. It
must not invoke `talosctl upgrade-k8s` while ArgoCD owns runtime Kubernetes
manifests, including `kube-system/coredns`.

Talos `upgrade-k8s` is not limited to control-plane binary versions: it also
reconciles Talos bootstrap manifests. On Vixens that would overwrite the
ArgoCD-owned CoreDNS runtime Corefile, creating a DNS outage and a controller
ownership conflict. `--manifests-no-prune` prevents deletions only; it does not
prevent updates to an existing ConfigMap.

## Required future design before re-enabling upgrades

A Kubernetes upgrade implementation must first provide all of the following:

1. one authoritative owner for every Talos bootstrap manifest and every
   GitOps runtime object;
2. a migration plan for existing clusters whose Talos owning inventory is
   empty, without adoption or overwrite of ArgoCD-owned resources;
3. a saved-plan/preflight that fails before any mutation when an ArgoCD-tracked
   object would be touched;
4. an end-to-end disposable-cluster test proving CoreDNS keeps resolving both
   `cluster.local` and the configured infrastructure upstream during upgrade;
5. a serial, health-gated rollout and a post-upgrade proof of API version and
   every node kubelet version.

Until that implementation exists, `kubernetes_version` is inventory metadata,
not an apply trigger. A version change requires a separately reviewed
maintenance implementation; Terraform will never silently invoke the unsafe
Talos transaction.
