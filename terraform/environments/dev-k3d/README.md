# Dev K3d platform

This is one self-contained Terraform root for the disposable Vixens development platform.

```bash
cd terraform/environments/dev-k3d
terraform init
terraform apply
terraform destroy
```

`apply` creates the `vixens-dev` K3d cluster, writes its generated kubeconfig to `.runtime/kubeconfig.yaml`, waits for the API, then installs Cilium, the four dev storage-class contracts, OpenBao bootstrap material, ArgoCD, and the GitOps root Application.

`destroy` removes that same Terraform graph and finally removes the K3d cluster. No `kubeconfig_path` input exists: the generated credential is internal to this root and is stored as a sensitive Terraform value plus a `0600` local runtime file.

The only out-of-Git prerequisite is the existing `~/.secrets/vixens-dev/openbao-token.yaml`, mode `0600`:

```yaml
stringData:
  token: <dev-openbao-token>
```

This token remains outside Git. Its path is deterministic for the account running Terraform and is not an input variable.

The old `cluster/`, `networking/`, and `gitops/` roots are retired. Do not apply them once this root is adopted.
