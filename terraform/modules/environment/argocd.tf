# ============================================================================
# ARGOCD GITOPS CONFIGURATION
# ============================================================================

module "argocd" {
  source = "../argocd"

  chart_version = module.shared.chart_versions.argocd
  environment   = var.environment
  git_branch    = var.git_branch

  argocd_config = var.argocd

  # DRY: Tolerations from shared module
  control_plane_tolerations = module.shared.control_plane_tolerations
  timeout                   = module.shared.timeouts.helm_install

  # Infisical bootstrap secret (optional)
  infisical_secret_path = var.paths.infisical_secret

  kubeconfig_path        = var.paths.kubeconfig
  cilium_module          = module.cilium
  root_app_template_path = "${path.module}/../../manifests/argocd/root-app.yaml.tpl"

  depends_on = [
    module.cilium
  ]
}

# Cross-validation: Ensure LoadBalancer IP in tfvars matches hardcoded manifest value
# This prevents runtime errors from IP mismatch between Terraform config and ArgoCD manifests
check "argocd_loadbalancer_ip_consistency" {
  assert {
    condition     = var.argocd.loadbalancer_ip == "192.168.208.71"
    error_message = "ArgoCD LoadBalancer IP in terraform.tfvars must be 192.168.208.71 to match the hardcoded value in argocd-server-service.yaml"
  }
}
