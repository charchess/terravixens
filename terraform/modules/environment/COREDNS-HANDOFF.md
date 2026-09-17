# CoreDNS ownership handoff

Terraform owns `kubectl_manifest.coredns_bootstrap[0]` only while ArgoCD is
unavailable. Its upstreams are supplied by the private production tfvars:

```hcl
coredns_bootstrap = {
  enabled   = true
  upstreams = ["192.168.201.1"]
}
```

After ArgoCD has reconciled the Vixens CoreDNS Application and the runtime
Corefile has been verified, set `enabled = false` in the private tfvars.

Do **not** apply that disabled configuration while Terraform still tracks the
ConfigMap: Terraform would delete it. First archive and inspect the remote
state, then remove only `kubectl_manifest.coredns_bootstrap[0]` from state,
read back its absence, and only then run the disabled Terraform configuration.
This is an explicit state mutation and requires separate approval.