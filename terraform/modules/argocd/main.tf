# ============================================================================
# ARGOCD MODULE - SELF-MANAGED BOOTSTRAP (v3.3.0)
# ============================================================================
# This module bootstraps ArgoCD from a local manifest and hands over control
# to GitOps via the App-of-Apps pattern.

# ----------------------------------------------------------------------------
# 0. NAMESPACE
# ----------------------------------------------------------------------------
# Ensure the ArgoCD namespace exists before creating any resources in it.
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

locals {
  argocd_manifests = [
    for f in fileset("${path.module}/bootstrap/manifests", "*.yaml") :
    f
    if !contains(["applications-argoproj-io.yaml", "applicationsets-argoproj-io.yaml", "appprojects-argoproj-io.yaml"], f)
  ]
}

# ----------------------------------------------------------------------------
# 1. CRDs (apply with kubectl --server-side for large CRDs)
# ----------------------------------------------------------------------------
resource "null_resource" "argocd_crds" {

  provisioner "local-exec" {
    command = <<-EOT
      KUBECONFIG=${var.kubeconfig_path} kubectl apply --server-side --force-conflicts -f "${path.module}/bootstrap/manifests/applications-argoproj-io.yaml" --field-manager=terraform --validate=false 2>/dev/null || true
      KUBECONFIG=${var.kubeconfig_path} kubectl apply --server-side --force-conflicts -f "${path.module}/bootstrap/manifests/applicationsets-argoproj-io.yaml" --field-manager=terraform --validate=false 2>/dev/null || true
      KUBECONFIG=${var.kubeconfig_path} kubectl apply --server-side --force-conflicts -f "${path.module}/bootstrap/manifests/appprojects-argoproj-io.yaml" --field-manager=terraform --validate=false 2>/dev/null || true
    EOT
  }

  depends_on = [kubernetes_namespace.argocd, var.cilium_module]
}

# ----------------------------------------------------------------------------
# 1b. PRE-DESTROY CLEANUP
# ----------------------------------------------------------------------------
# This resource ensures proper cleanup order during destroy:
# 1. Delete ArgoCD Applications (with finalizers)
# 2. Delete ArgoCD CRDs
# 3. Wait for namespace to be empty
# This prevents namespace stuck in "Terminating" state.

resource "null_resource" "argocd_pre_destroy_cleanup" {
  # Triggers ensure this resource is recreated when critical components change
  triggers = {
    kubeconfig_path = var.kubeconfig_path
    namespace       = var.namespace
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue # Don't block destroy if cleanup fails
    command    = <<-EOT
      set -e
      
      KUBECONFIG="${self.triggers.kubeconfig_path}"
      NAMESPACE="${self.triggers.namespace}"
      
      echo "=== ArgoCD Pre-Destroy Cleanup Started ==="
      
      # Step 1: Delete all ArgoCD Applications (these have finalizers that block namespace deletion)
      echo "Step 1/4: Deleting ArgoCD Applications..."
      kubectl --kubeconfig "$KUBECONFIG" delete applications.argoproj.io \
        --all -n "$NAMESPACE" \
        --grace-period=30 \
        --timeout=3m \
        2>/dev/null || echo "Warning: No applications found or already deleted"
      
      # Step 2: Wait for Applications to be fully deleted
      echo "Step 2/4: Waiting for Applications to be deleted..."
      kubectl --kubeconfig "$KUBECONFIG" wait \
        --for=delete applications.argoproj.io \
        --all -n "$NAMESPACE" \
        --timeout=2m \
        2>/dev/null || echo "Warning: Wait timed out or no applications"
      
      # Step 3: Delete ArgoCD CRDs (must be done before namespace deletion)
      echo "Step 3/4: Deleting ArgoCD CRDs..."
      kubectl --kubeconfig "$KUBECONFIG" delete crd \
        applications.argoproj.io \
        applicationsets.argoproj.io \
        appprojects.argoproj.io \
        --ignore-not-found=true \
        --timeout=2m \
        2>/dev/null || echo "Warning: CRDs already deleted or not found"
      
      # Step 4: Wait for CRDs to be fully removed
      echo "Step 4/4: Waiting for CRDs to be deleted..."
      for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
        kubectl --kubeconfig "$KUBECONFIG" wait --for=delete crd "$crd" --timeout=1m 2>/dev/null || true
      done
      
      echo "=== ArgoCD Pre-Destroy Cleanup Completed ==="
    EOT
  }

  # This resource must be destroyed AFTER all ArgoCD resources are destroyed
  # but BEFORE the CRDs and namespace are destroyed
  depends_on = [
    kubectl_manifest.argocd_root_app,
    kubectl_manifest.argocd_params_bootstrap,
    kubectl_manifest.argocd_core
  ]
}

# ----------------------------------------------------------------------------
# 2. CORE ENGINE (SEED)
# ----------------------------------------------------------------------------
# Apply the monolith v3.3.0 manifest provided in the bootstrap directory.
resource "kubectl_manifest" "argocd_core" {
  for_each  = toset(local.argocd_manifests)
  yaml_body = file("${path.module}/bootstrap/manifests/${each.value}")

  # CRITICAL: We ignore subsequent changes to let ArgoCD manage itself via GitOps.
  # Terraform is only responsible for the INITIAL installation of the engine.
  lifecycle {
    ignore_changes = all
  }

  depends_on = [
    kubernetes_namespace.argocd,
    null_resource.argocd_crds,
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
  depends_on = [null_resource.argocd_crds, kubectl_manifest.argocd_core]
}

# ----------------------------------------------------------------------------
# 2b. ANONYMOUS ADMIN ACCESS (OPTIONAL)
# ----------------------------------------------------------------------------
# When anonymous_enabled=true, configure ArgoCD for no-auth admin access
# This requires both argocd-cm and argocd-rbac-cm to be configured

resource "kubectl_manifest" "argocd_cm_anonymous" {
  count = var.argocd_config.anonymous_enabled ? 1 : 0

  yaml_body = <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cm
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: argocd-cm
        app.kubernetes.io/part-of: argocd
    data:
      users.anonymous.enabled: "true"
  EOF

  depends_on = [kubectl_manifest.argocd_core]
}

resource "kubectl_manifest" "argocd_rbac_cm_anonymous" {
  count = var.argocd_config.anonymous_enabled ? 1 : 0

  yaml_body = <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-rbac-cm
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: argocd-rbac-cm
        app.kubernetes.io/part-of: argocd
    data:
      policy.default: role:admin
      policy.csv: ""
  EOF

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
    null_resource.argocd_crds,
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
    null_resource.argocd_crds,
    kubectl_manifest.argocd_params_bootstrap,
    kubernetes_secret_v1.infisical_universal_auth
  ]
}
