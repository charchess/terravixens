# ============================================================================
# CILIUM CNI CONFIGURATION
# ============================================================================

module "cilium" {
  source = "../cilium"

  chart_version = module.shared.chart_versions.cilium

  # DRY: Capabilities from shared module
  cilium_agent_capabilities = module.shared.cilium_config.agent_capabilities
  cilium_clean_capabilities = module.shared.cilium_config.clean_capabilities
  control_plane_tolerations = module.shared.control_plane_tolerations

  timeout = module.shared.timeouts.helm_install

  talos_cluster_module = module.talos_cluster
  wait_for_k8s_api     = null_resource.wait_for_k8s_api

  cilium_l2 = var.cilium_l2
  platform = {
    name                     = "talos"
    k8s_service_host         = "localhost"
    k8s_service_port         = 7445
    kube_proxy_replacement   = true
    l2_announcements_enabled = true
    external_ips_enabled     = true
  }

  kubeconfig_path = var.paths.kubeconfig
}
