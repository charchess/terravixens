# ============================================================================
# ARGOCD MODULE VARIABLES
# ============================================================================

variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "environment" {
  description = "Environment name (dev, test, staging, prod)"
  type        = string
}

variable "bootstrap_seed_enabled" {
  description = "Create Terraform ArgoCD bootstrap seeds; disable after GitOps ownership is established."
  type        = bool
  default     = true
}

variable "git_branch" {
  description = "Git branch for ArgoCD to track"
  type        = string
}

# --------------------------------------------------------------------------
# ARGOCD CONFIGURATION (typed object)
# --------------------------------------------------------------------------
variable "argocd_config" {
  description = "ArgoCD configuration object"
  type = object({
    service_type      = string
    loadbalancer_ip   = string
    hostname          = string
    insecure          = bool
    disable_auth      = bool
    anonymous_enabled = bool
    self_heal         = optional(bool, true)
  })

  # NOTE: LoadBalancer IP is hardcoded in bootstrap manifest for initial deployment
  # After bootstrap, ArgoCD self-manages via GitOps and can override this value
  # The lifecycle { ignore_changes = all } on argocd_core ensures Terraform doesn't revert GitOps changes
}

# --------------------------------------------------------------------------
# DRY CONFIGURATION
# --------------------------------------------------------------------------
variable "control_plane_tolerations" {
  description = "Control plane tolerations (from shared module)"
  type = list(object({
    key      = string
    operator = string
    effect   = string
  }))
}

variable "timeout" {
  description = "Helm installation timeout (seconds)"
  type        = number
  default     = 600
}

# --------------------------------------------------------------------------
# DEPENDENCIES
# --------------------------------------------------------------------------
variable "cilium_module" {
  description = "Cilium module reference for dependency"
  type        = any
  default     = null
}

variable "root_app_template_path" {
  description = "Path to root-app.yaml.tpl template"
  type        = string
}

variable "openbao_bootstrap_token_path" {
  description = "Ignored YAML file containing stringData.token for external-secrets/openbao-token"
  type        = string

  validation {
    condition = fileexists(var.openbao_bootstrap_token_path) && can(
      trimspace(yamldecode(file(var.openbao_bootstrap_token_path)).stringData.token)
    ) && trimspace(yamldecode(file(var.openbao_bootstrap_token_path)).stringData.token) != ""
    error_message = "OpenBao bootstrap token file must exist outside Git and contain a non-empty stringData.token."
  }
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
}
