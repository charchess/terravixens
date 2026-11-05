output "cluster_name" {
  value = k3d_cluster.dev.name
}

output "kubeconfig_path" {
  value = local_sensitive_file.kubeconfig.filename
}

output "api_host" {
  value = k3d_cluster.dev.host
}
