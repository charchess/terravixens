# ============================================================================
# ARGOCD GITOPS CONFIGURATION
# ============================================================================

module "argocd" {
  source = "../argocd"

  chart_version          = module.shared.chart_versions.argocd
  environment            = var.environment
  git_branch             = var.git_branch
  bootstrap_seed_enabled = var.argocd_bootstrap_seed_enabled

  argocd_config = var.argocd

  # DRY: Tolerations from shared module
  control_plane_tolerations = module.shared.control_plane_tolerations
  timeout                   = module.shared.timeouts.helm_install

  openbao_bootstrap_token_path = var.paths.openbao_bootstrap_token
  kubeconfig_path              = var.paths.kubeconfig
  cilium_module                = module.cilium
  root_app_template_path       = "${path.module}/../../manifests/argocd/root-app.yaml.tpl"

  depends_on = [
    module.cilium
  ]
}

# NOTE: LoadBalancer IP validation removed to support multiple environments
# Each environment can use its own IP range (dev: 192.168.208.x, prod: 192.168.201.x)
# After bootstrap, ArgoCD self-manages its service configuration via GitOps
