# ============================================================================
# CILIUM MODULE VARIABLES - OPTIMIZED
# ============================================================================

variable "release_name" {
  description = "Helm release name for Cilium"
  type        = string
  default     = "cilium"
}

variable "chart_version" {
  description = "Cilium Helm chart version (from shared module)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Cilium"
  type        = string
  default     = "kube-system"
}

# --------------------------------------------------------------------------
# DRY CONFIGURATIONS (from shared module)
# --------------------------------------------------------------------------
variable "cilium_agent_capabilities" {
  description = "Cilium agent capabilities (from shared module)"
  type = object({
    add  = list(string)
    drop = list(string)
  })
}

variable "cilium_clean_capabilities" {
  description = "Cilium cleanState capabilities (from shared module)"
  type = object({
    add  = list(string)
    drop = list(string)
  })
}

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
  default     = 900
}

# --------------------------------------------------------------------------
# DEPENDENCIES
# --------------------------------------------------------------------------
variable "talos_cluster_module" {
  description = "Talos cluster module reference"
  type        = any
  default     = null
}

variable "wait_for_k8s_api" {
  description = "Wait for K8s API resource reference"
  type        = any
  default     = null
}

# --------------------------------------------------------------------------
# CILIUM L2 ANNOUNCEMENTS
# --------------------------------------------------------------------------
variable "cilium_l2" {
  description = "Cilium L2 Announcements configuration"
  type = object({
    pool_name     = string
    pool_ips      = list(string)
    policy_name   = string
    interfaces    = list(string)
    node_selector = map(string)
  })
}

# --------------------------------------------------------------------------
# FILE PATHS
# --------------------------------------------------------------------------
variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
}
