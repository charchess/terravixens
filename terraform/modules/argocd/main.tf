# ============================================================================
# ARGOCD MODULE - SELF-MANAGED BOOTSTRAP (v3.3.0)
# ============================================================================
# This module bootstraps ArgoCD from a local manifest and hands over control
# to GitOps via the App-of-Apps pattern.

# ----------------------------------------------------------------------------
# 1. CORE ENGINE (SEED)
# ----------------------------------------------------------------------------
# Apply the monolith v3.3.0 manifest provided in the bootstrap directory.
# We use kubectl_file_documents to split the large YAML and apply it efficiently.

data "kubectl_file_documents" "argocd_install" {
  content = file("${path.module}/bootstrap/install.yaml")
}

resource "kubectl_manifest" "argocd_core" {
  for_each  = data.kubectl_file_documents.argocd_install.manifests
  yaml_body = each.value

  # CRITICAL: We ignore subsequent changes to let ArgoCD manage itself via GitOps.
  # Terraform is only responsible for the INITIAL installation of the engine.
  lifecycle {
    ignore_changes = all
  }

  depends_on = [
    var.cilium_module
  ]
}

# ----------------------------------------------------------------------------
# 2. INITIAL CONFIGURATION (INSECURE / NO-AUTH)
# ----------------------------------------------------------------------------
# To ensure immediate access after the bootstrap, we inject the insecure/no-auth
# settings directly into the ConfigMap. This overrides any default from the manifest.

resource "kubectl_manifest" "argocd_params_bootstrap" {
  yaml_body = <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cmd-params-cm
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: argocd-cmd-params-cm
        app.kubernetes.io/part-of: argocd
        managed-by: terraform
    data:
      server.insecure: "${var.argocd_config.insecure ? "true" : "false"}"
      server.disable.auth: "${var.argocd_config.disable_auth ? "true" : "false"}"
  EOF

  # Ensure the ConfigMap exists before we try to patch it or rely on it
  depends_on = [kubectl_manifest.argocd_core]
}

# ----------------------------------------------------------------------------
# 3. INFISICAL UNIVERSAL AUTH SECRET (BOOTSTRAP)
# ----------------------------------------------------------------------------
# Deploy Infisical credentials secret before root-app to enable InfisicalSecret CRDs
# This is a prerequisite for ArgoCD to sync apps that use Infisical secrets.

resource "kubernetes_secret_v1" "infisical_universal_auth" {
  count = var.infisical_secret_path != "" ? 1 : 0

  metadata {
    name      = "infisical-universal-auth"
    namespace = var.namespace

    labels = {
      "app"        = "infisical-operator"
      "managed-by" = "terraform"
    }
  }

  data = {
    clientId     = yamldecode(file(var.infisical_secret_path)).stringData.clientId
    clientSecret = yamldecode(file(var.infisical_secret_path)).stringData.clientSecret
  }

  type = "Opaque"

  depends_on = [
    kubectl_manifest.argocd_core
  ]
}

# ----------------------------------------------------------------------------
# 4. ROOT APPLICATION (ACTIVATION)
# ----------------------------------------------------------------------------
# This creates the Application named 'vixens-app-of-apps'.
# It points ArgoCD to Git for full self-management.

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = templatefile(var.root_app_template_path, {
    environment     = var.environment
    target_revision = var.git_branch
    overlay_path    = "argocd/overlays/${var.environment}"
    self_heal       = var.argocd_config.self_heal
  })

  depends_on = [
    kubectl_manifest.argocd_params_bootstrap,
    kubernetes_secret_v1.infisical_universal_auth
  ]
}
