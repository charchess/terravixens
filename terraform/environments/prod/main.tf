# ============================================================================
# VIXENS DEV ENVIRONMENT
# ============================================================================
# Uses the shared environment module for DRY infrastructure deployment

module "environment" {
  source = "../../modules/environment"

  environment                   = var.environment
  git_branch                    = var.git_branch
  argocd_bootstrap_seed_enabled = false
  cluster                       = var.cluster
  control_plane_nodes           = var.control_plane_nodes
  control_plane_rollout_order   = var.control_plane_rollout_order
  talos_rollout_enabled         = var.talos_rollout_enabled
  worker_nodes                  = var.worker_nodes
  paths                         = var.paths
  argocd                        = var.argocd
  cilium_l2                     = var.cilium_l2
  coredns_bootstrap             = var.coredns_bootstrap
}
