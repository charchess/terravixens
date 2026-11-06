locals {
  cluster_name                 = "vixens-dev"
  kubeconfig_path              = "${path.root}/.runtime/kubeconfig.yaml"
  openbao_bootstrap_token_path = pathexpand("~/.secrets/vixens-dev/openbao-token.yaml")
  dns_upstreams                = ["192.168.200.69", "1.1.1.1"]

  coredns_corefile = <<-CORE
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
        forward . ${join(" ", local.dns_upstreams)}
    }
  CORE
}

resource "k3d_cluster" "dev" {
  name = local.cluster_name

  k3d_config = yamlencode({
    apiVersion = "k3d.io/v1alpha5"
    kind       = "Simple"
    metadata   = { name = local.cluster_name }
    servers    = 1
    agents     = 1
    image      = "rancher/k3s:v1.35.5-k3s1"
    kubeAPI = {
      host     = "127.0.0.1"
      hostIP   = "127.0.0.1"
      hostPort = "6445"
    }
    options = {
      k3s = {
        extraArgs = [
          { arg = "--flannel-backend=none", nodeFilters = ["server:*"] },
          { arg = "--disable-network-policy", nodeFilters = ["server:*"] },
          { arg = "--disable-kube-proxy", nodeFilters = ["server:*"] },
          { arg = "--tls-san=k3d-vixens-dev-server-0", nodeFilters = ["server:*"] },
        ]
      }
      k3d = { wait = true }
      kubeconfig = {
        updateDefaultKubeconfig = false
        switchCurrentContext    = false
      }
    }
  })
}

resource "local_sensitive_file" "kubeconfig" {
  content              = k3d_cluster.dev.kubeconfig
  filename             = local.kubeconfig_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "terraform_data" "api_ready" {
  input = { kubeconfig_path = local_sensitive_file.kubeconfig.filename }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${self.input.kubeconfig_path} get --raw=/readyz"
  }
}

resource "kubectl_manifest" "coredns" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata   = { name = "coredns", namespace = "kube-system" }
    data       = { Corefile = local.coredns_corefile }
  })

  depends_on = [terraform_data.api_ready]
}

module "cilium" {
  source = "../../modules/cilium"

  chart_version = "1.20.2"
  cilium_agent_capabilities = {
    add  = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
    drop = ["ALL"]
  }
  cilium_clean_capabilities = {
    add  = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
    drop = ["ALL"]
  }
  control_plane_tolerations = []
  timeout                   = 1200
  kubeconfig_path           = local.kubeconfig_path
  wait_for_k8s_api          = terraform_data.api_ready
  wait_for_cilium_crds      = false
  cilium_l2                 = null
  platform = {
    name                     = "k3d"
    k8s_service_host         = "k3d-vixens-dev-server-0"
    k8s_service_port         = 6443
    kube_proxy_replacement   = true
    l2_announcements_enabled = false
    external_ips_enabled     = false
  }

  depends_on = [kubectl_manifest.coredns]
}

resource "terraform_data" "cilium_ready" {
  input = { kubeconfig_path = local.kubeconfig_path }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${self.input.kubeconfig_path} -n kube-system rollout status daemonset/cilium --timeout=10m"
  }

  depends_on = [module.cilium]
}

resource "kubernetes_storage_class_v1" "local_path_contract" {
  for_each = {
    "storage-rwo-delete" = "Delete"
    "storage-rwo-retain" = "Retain"
    "storage-rwx-delete" = "Delete"
    "storage-rwx-retain" = "Retain"
  }

  metadata { name = each.key }
  storage_provisioner    = "rancher.io/local-path"
  reclaim_policy         = each.value
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  depends_on = [terraform_data.cilium_ready]
}

module "argocd" {
  source = "../../modules/argocd"

  chart_version          = "7.7.7"
  environment            = "dev"
  git_branch             = "main"
  git_repository_url     = "https://github.com/charchess/vixens-core.git"
  bootstrap_seed_enabled = true
  argocd_config = {
    service_type      = "ClusterIP"
    loadbalancer_ip   = ""
    hostname          = ""
    insecure          = false
    disable_auth      = false
    anonymous_enabled = false
    self_heal         = true
  }
  control_plane_tolerations    = []
  timeout                      = 600
  kubeconfig_path              = local.kubeconfig_path
  openbao_bootstrap_token_path = local.openbao_bootstrap_token_path
  root_app_template_path       = "${path.module}/../../manifests/argocd/root-app.yaml.tpl"
  cilium_module                = terraform_data.cilium_ready

  depends_on = [kubernetes_storage_class_v1.local_path_contract]
}
