resource "k3d_cluster" "dev" {
  name = var.cluster_name

  k3d_config = yamlencode({
    apiVersion = "k3d.io/v1alpha5"
    kind       = "Simple"
    metadata   = { name = var.cluster_name }
    servers    = var.servers
    agents     = var.agents
    image      = var.k3s_image
    kubeAPI = {
      host     = "127.0.0.1"
      hostIP   = "127.0.0.1"
      hostPort = var.api_host_port
    }
    options = {
      k3s = {
        extraArgs = [
          { arg = "--flannel-backend=none", nodeFilters = ["server:*"] },
          { arg = "--disable-network-policy", nodeFilters = ["server:*"] },
          { arg = "--disable-kube-proxy", nodeFilters = ["server:*"] },
          { arg = "--tls-san=k3d-${var.cluster_name}-server-0", nodeFilters = ["server:*"] },
        ]
      }
      k3d = {
        wait = true
      }
      kubeconfig = {
        updateDefaultKubeconfig = false
        switchCurrentContext    = false
      }
    }
  })
}

resource "local_sensitive_file" "kubeconfig" {
  content              = k3d_cluster.dev.kubeconfig
  filename             = var.kubeconfig_path
  file_permission      = "0600"
  directory_permission = "0700"
}
