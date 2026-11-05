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

module "argocd" {
  count  = var.bootstrap_enabled ? 1 : 0
  source = "../../modules/argocd"

  chart_version          = var.argocd_chart_version
  environment            = var.environment
  git_branch             = var.git_branch
  bootstrap_seed_enabled = true
  argocd_config          = var.argocd

  control_plane_tolerations    = []
  timeout                      = var.argocd_timeout_seconds
  kubeconfig_path              = var.kubeconfig_path
  openbao_bootstrap_token_path = var.openbao_bootstrap_token_path
  root_app_template_path       = "${path.module}/../../manifests/argocd/root-app.yaml.tpl"

  # The existing module uses this dependency name for the network-ready gate.
  # In K3s, API readiness replaces the Talos/Cilium bootstrap dependency.
  cilium_module = terraform_data.k3s_api_ready[0]
}
