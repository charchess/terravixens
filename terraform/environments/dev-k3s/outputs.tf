output "environment" {
  value = var.environment
}

output "storage_class_name" {
  description = "Storage contract selected for Vixens dev workloads."
  value       = var.storage_class_name
}

output "bootstrap_enabled" {
  description = "Whether this run is permitted to create the initial ArgoCD bootstrap resources."
  value       = var.bootstrap_enabled
}
