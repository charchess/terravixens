resource "terraform_data" "api_ready" {
  input = {
    kubeconfig_path = var.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${self.input.kubeconfig_path} get --raw=/readyz"
  }
}

locals {
  coredns_k3d_corefile = <<-CORE
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
        }
        hosts /etc/coredns/NodeHosts {
            ttl 60
            reload 15s
            fallthrough
        }
        prometheus :9153
        cache 30
        loop
        reload
        loadbalance
        forward . ${join(" ", var.dns_upstreams)}
    }
  CORE
}

resource "kubectl_manifest" "coredns_k3d" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "coredns"
      namespace = "kube-system"
    }
    data = {
      Corefile = local.coredns_k3d_corefile
    }
  })

  depends_on = [terraform_data.api_ready]
}

module "cilium" {
  source = "../../../modules/cilium"

  chart_version             = var.cilium_chart_version
  cilium_agent_capabilities = var.cilium_agent_capabilities
  cilium_clean_capabilities = var.cilium_clean_capabilities
  control_plane_tolerations = []
  timeout                   = var.cilium_timeout_seconds
  kubeconfig_path           = var.kubeconfig_path
  wait_for_k8s_api          = terraform_data.api_ready
  wait_for_cilium_crds      = false
  cilium_l2                 = null
  platform = {
    name                     = "k3d"
    k8s_service_host         = var.k8s_service_host
    k8s_service_port         = 6443
    kube_proxy_replacement   = true
    l2_announcements_enabled = false
    external_ips_enabled     = false
  }

  depends_on = [kubectl_manifest.coredns_k3d]
}
