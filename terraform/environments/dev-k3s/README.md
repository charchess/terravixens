# Vixens dev on K3s

This root prepares the **dev** Vixens environment against an existing K3s API. It does not provision K3s, Talos nodes, Cilium, a NAS, or a TrueNAS CSI driver.

## Safety contract

- State is intentionally local at `state/terraform.tfstate` on the Lab VM that owns the K3d target; it is excluded from Git and never reads a Talos or production state backend.
- The Kubernetes, Helm, and kubectl providers use only the runtime-supplied K3s kubeconfig.
- `bootstrap_enabled` defaults to `false`. A normal review plan is inert; bootstrap requires an explicit `-var='bootstrap_enabled=true'`.
- No backend credentials exist in `backend.tf`, tfvars, or Git.
- The initial ArgoCD service is `ClusterIP`; exposing it is a separate reviewed network change.
- The dev target publishes all four `storage-rwo-*` and `storage-rwx-*` contract names over `rancher.io/local-path`. On this single-host K3d target, `storage-rwx-*` is deliberate local emulation only, not portable or HA.

## Preflight

Resolve the non-secret paths through the approved Lab operator authority, then run from this directory on the Lab VM:

```bash
terraform init -reconfigure -input=false
terraform validate
terraform plan -refresh=true -lock=true -input=false \
  -var="kubeconfig_path=/protected/path/to/dev-k3s.kubeconfig"
```

Before enabling the bootstrap, prove all of the following:

1. the kubeconfig context and API server identify the intended K3s dev target;
2. the `local-path-delete` StorageClass exists (or the reviewed selected local-path class);
3. `argocd/overlays/dev` exists in the reviewed Vixens Git revision;
4. the dev-scoped OpenBao bootstrap file exists outside Git and is non-empty;
5. the plan JSON contains only the reviewed ArgoCD/External Secrets bootstrap resources.

Only then is an explicitly approved bootstrap allowed:

```bash
terraform apply -input=false -lock=true \
  -var="kubeconfig_path=/protected/path/to/dev-k3s.kubeconfig" \
  -var='bootstrap_enabled=true'
```

The Vixens dev overlay must consume the `local-path-*` contract before stateful applications are enabled. This Terraform root does not mutate Vixens manifests.
