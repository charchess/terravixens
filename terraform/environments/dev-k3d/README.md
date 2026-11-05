# Vixens dev K3d platform lifecycle

Dev mirrors the production ownership order while replacing Talos machines with a Terraform-owned K3d cluster:

```text
K3d cluster -> Cilium -> Storage and ArgoCD bootstrap -> vixens-core GitOps
```

The roots are intentionally separate because Kubernetes and Helm providers must not initialize before K3d has created a reachable API and a protected kubeconfig.

- `cluster/` owns only Docker/K3d lifecycle and writes the runner-local `0600` kubeconfig.
- `networking/` owns Cilium. K3d disables Flannel, the K3s NetworkPolicy controller, and kube-proxy; Cilium uses the K3d-internal API endpoint and kube-proxy replacement. It does not create production L2/pool resources.
- `gitops/` owns the four local-path storage contract names, the dev-scoped OpenBao bootstrap secret, ArgoCD, and the root Application. It refuses bootstrap until Cilium is Ready.

Use the single operational entrypoint from the Lab runner:

```bash
./scripts/dev-k3d apply
./scripts/dev-k3d destroy
```

`destroy` preserves Terraform's normal confirmation prompts but handles the safe internal order itself: GitOps, then Cilium/networking, then the K3d cluster. It never reads Talos or production state.

## State recovery

The pre-refactor `dev-k3s` state was quarantined on the Lab runner after the K3d cluster disappeared. Do not apply or destroy that old root. A new cluster/networking/gitops lifecycle starts from fresh per-root states; only resources proven live may ever be imported into a new root.
