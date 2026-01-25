# ============================================================================
# PROVIDERS CONFIGURATION
# ============================================================================

provider "helm" {
  kubernetes = {
    # Use the real IP of the first CP node for maximum robustness
    host                   = "https://192.168.111.162:6443"
    client_certificate     = base64decode(module.environment.talos_cluster.kubernetes_client_certificate)
    client_key             = base64decode(module.environment.talos_cluster.kubernetes_client_key)
    cluster_ca_certificate = base64decode(module.environment.talos_cluster.kubernetes_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://192.168.111.162:6443"
  client_certificate     = base64decode(module.environment.talos_cluster.kubernetes_client_certificate)
  client_key             = base64decode(module.environment.talos_cluster.kubernetes_client_key)
  cluster_ca_certificate = base64decode(module.environment.talos_cluster.kubernetes_ca_certificate)
  load_config_file       = false
}

provider "kubernetes" {
  host                   = "https://192.168.111.162:6443"
  client_certificate     = base64decode(module.environment.talos_cluster.kubernetes_client_certificate)
  client_key             = base64decode(module.environment.talos_cluster.kubernetes_client_key)
  cluster_ca_certificate = base64decode(module.environment.talos_cluster.kubernetes_ca_certificate)
}
