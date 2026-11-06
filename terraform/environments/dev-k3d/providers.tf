provider "kubernetes" {
  host                   = k3d_cluster.dev.host
  client_certificate     = base64decode(k3d_cluster.dev.client_certificate)
  client_key             = base64decode(k3d_cluster.dev.client_key)
  cluster_ca_certificate = base64decode(k3d_cluster.dev.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = k3d_cluster.dev.host
    client_certificate     = base64decode(k3d_cluster.dev.client_certificate)
    client_key             = base64decode(k3d_cluster.dev.client_key)
    cluster_ca_certificate = base64decode(k3d_cluster.dev.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = k3d_cluster.dev.host
  client_certificate     = base64decode(k3d_cluster.dev.client_certificate)
  client_key             = base64decode(k3d_cluster.dev.client_key)
  cluster_ca_certificate = base64decode(k3d_cluster.dev.cluster_ca_certificate)
  load_config_file       = false
  apply_retry_count      = 15
}
