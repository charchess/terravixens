# ============================================================================
# COREDNS BOOTSTRAP HANDOFF
# ============================================================================
# Terraform seeds only a minimal recursive CoreDNS configuration needed to let
# ArgoCD reach Git, registries, and OpenBao on a new cluster. It deliberately
# does NOT own the ConfigMap in Terraform state: when this one-shot bootstrap is
# disabled, Terraform removes only its local execution marker, never CoreDNS.
# ArgoCD becomes the sole runtime owner of kube-system/coredns.

locals {
  coredns_bootstrap_corefile = <<-CORE
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        prometheus :9153
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        forward . ${join(" ", var.coredns_bootstrap.upstreams)} {
            max_concurrent 1000
        }
        cache 30 {
            disable success cluster.local
            disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
  CORE

  coredns_bootstrap_manifest = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "coredns"
      namespace = "kube-system"
      labels = {
        "app.kubernetes.io/name"       = "coredns"
        "app.kubernetes.io/managed-by" = "terraform-bootstrap"
      }
      annotations = {
        "vixens.truxonline.com/ownership-handoff" = "ArgoCD owns this ConfigMap after bootstrap"
      }
    }
    data = {
      Corefile = local.coredns_bootstrap_corefile
    }
  })
}

# terraform_data records execution only; it has no remote CoreDNS identity.
# Its destroy path is intentionally empty, so disabling bootstrap is a safe
# state handoff rather than a ConfigMap deletion.
resource "terraform_data" "coredns_bootstrap" {
  count = var.coredns_bootstrap.enabled ? 1 : 0

  triggers_replace = [
    sha256(local.coredns_bootstrap_manifest),
    var.paths.kubeconfig,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = var.paths.kubeconfig
    }
    command = <<-EOT
      set -euo pipefail
      cat <<'MANIFEST' | kubectl apply --server-side --field-manager=terraform-bootstrap -f -
      ${local.coredns_bootstrap_manifest}
      MANIFEST

      kubectl -n kube-system rollout status deployment/coredns --timeout=5m
      corefile="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
      ${join("\n      ", [for upstream in var.coredns_bootstrap.upstreams : "grep -Fq '${upstream}' <<<\"$corefile\""])}
    EOT
  }

  depends_on = [null_resource.wait_for_k8s_api]
}
