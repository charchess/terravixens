# Dev K3s bootstrap root. It never creates or reconciles Talos resources.

resource "terraform_data" "k3s_api_ready" {
  count = var.bootstrap_enabled ? 1 : 0

  input = {
    kubeconfig_path = var.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${self.input.kubeconfig_path} get --raw=/readyz"
  }
}

resource "terraform_data" "bootstrap_prerequisites" {
  count = var.bootstrap_enabled ? 1 : 0

  depends_on = [
    terraform_data.k3s_api_ready,
    kubernetes_storage_class_v1.local_path_contract,
  ]
}

# k3d supplies a local-path provisioner. In this single-host test environment,
# all platform contract names intentionally resolve to it, including RWX labels.
# The RWX labels are local emulation only: they are neither portable nor HA.
resource "kubernetes_storage_class_v1" "local_path_contract" {
  for_each = var.bootstrap_enabled ? {
    "storage-rwo-delete" = "Delete"
    "storage-rwo-retain" = "Retain"
    "storage-rwx-delete" = "Delete"
    "storage-rwx-retain" = "Retain"
  } : {}

  metadata {
    name = each.key
  }

  storage_provisioner    = "rancher.io/local-path"
  reclaim_policy         = each.value
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

module "argocd" {
  count  = var.bootstrap_enabled ? 1 : 0
  source = "../../modules/argocd"

  chart_version          = var.argocd_chart_version
  environment            = var.environment
  git_branch             = var.git_branch
  git_repository_url     = var.git_repository_url
  bootstrap_seed_enabled = true
  argocd_config          = var.argocd

  control_plane_tolerations    = []
  timeout                      = var.argocd_timeout_seconds
  kubeconfig_path              = var.kubeconfig_path
  openbao_bootstrap_token_path = var.openbao_bootstrap_token_path
  root_app_template_path       = "${path.module}/../../manifests/argocd/root-app.yaml.tpl"

  # The existing module uses this dependency name for the network-ready gate.
  # In K3s, API readiness replaces the Talos/Cilium bootstrap dependency.
  cilium_module = terraform_data.bootstrap_prerequisites[0]
}
