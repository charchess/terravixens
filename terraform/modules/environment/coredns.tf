# ============================================================================
# COREDNS UDM-ONLY BOOTSTRAP
# ============================================================================
# This resource exists only for the initial bootstrap, before ArgoCD can
# reconcile Vixens' runtime Corefile. Disable it before the ArgoCD handoff.

locals {
  coredns_bootstrap_corefile = <<-CORE
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        log . {
            class error
        }
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
}

resource "kubectl_manifest" "coredns_bootstrap" {
  count = var.coredns_bootstrap.enabled ? 1 : 0

  yaml_body = yamlencode({
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
        "vixens.truxonline.com/ownership-handoff" = "ArgoCD must own this ConfigMap after bootstrap"
      }
    }
    data = {
      Corefile = local.coredns_bootstrap_corefile
    }
  })

  depends_on = [null_resource.wait_for_k8s_api]
}