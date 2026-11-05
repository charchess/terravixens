# Vixens dev on K3s

This root prepares the **dev** Vixens environment against an existing K3s API. It does not provision K3s, Talos nodes, Cilium, a NAS, or a TrueNAS CSI driver.

## Safety contract

- State is isolated at `terraform-state-dev/k3s/terraform.tfstate`; it never reads the legacy Talos dev state key.
- The Kubernetes, Helm, and kubectl providers use only the runtime-supplied K3s kubeconfig.
- `bootstrap_enabled` defaults to `false`. A normal review plan is inert; bootstrap requires an explicit `-var='bootstrap_enabled=true'`.
- S3 credentials are process environment variables. No credential belongs in `backend.tf`, tfvars, or Git.
- The initial ArgoCD service is `ClusterIP`; exposing it is a separate reviewed network change.
- The dev storage contract is `local-path-delete` by default. Use `local-path-retain` only for state explicitly intended to survive routine dev cleanup.

## Preflight

Resolve the non-secret paths and S3 credentials through the approved operator authority, then run from this directory:

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
