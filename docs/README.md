# TerraVixens Documentation

Infrastructure documentation for Terraform and Talos Linux.

## Structure

- **procedures/** - Operational procedures (bootstrap, destroy/recreate, upgrades)
- **troubleshooting/** - Infrastructure troubleshooting guides

## Key Documentation

### Terraform Operations

**Standard workflow:**
```bash
cd terraform/environments/dev
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply
```

**Destroy/Recreate (dev/test only):**
```bash
terraform destroy -auto-approve
terraform apply -auto-approve
```

**Never destroy:** staging, prod (physical infrastructure)

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

## Related Documentation

**Application docs:** See [vixens/docs/](https://github.com/charchess/vixens/tree/main/docs)

**Cross-references:**
- Cluster bootstrap → This repo
- Application deployment → vixens repo
- Network architecture → This repo
- GitOps patterns → vixens repo
