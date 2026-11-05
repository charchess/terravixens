variable "environment" {
  description = "Vixens GitOps environment selected by the root Application."
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "The dev-k3s root may bootstrap only the dev GitOps overlay."
  }
}

variable "kubeconfig_path" {
  description = "Absolute path to the K3s kubeconfig. It is supplied at runtime and is never committed."
  type        = string
  sensitive   = true
}

variable "git_branch" {
  description = "Immutable or reviewed Vixens revision for the dev root Application."
  type        = string
  default     = "main"
}

variable "git_repository_url" {
  description = "Vixens GitOps repository used by the dev root Application."
  type        = string
  default     = "https://github.com/charchess/vixens-core.git"

  validation {
    condition     = var.git_repository_url == "https://github.com/charchess/vixens-core.git"
    error_message = "The dev K3d contract bootstraps only charchess/vixens-core."
  }
}

variable "bootstrap_enabled" {
  description = "Explicitly permit the initial K3s API check and ArgoCD bootstrap. Defaults to false so plans are inert."
  type        = bool
  default     = false
}

variable "openbao_bootstrap_token_path" {
  description = "Ignored YAML file containing stringData.token for the dev External Secrets bootstrap."
  type        = string
  default     = "../../../.secrets/dev/openbao-token.yaml"
}

variable "storage_class_name" {
  description = "Dev storage contract consumed by Vixens overlays; K3s local-path only."
  type        = string
  default     = "local-path-delete"

  validation {
    condition     = contains(["local-path-delete", "local-path-retain"], var.storage_class_name)
    error_message = "dev-k3s storage must be local-path-delete or local-path-retain."
  }
}

variable "argocd_chart_version" {
  description = "ArgoCD chart/manifest compatibility version recorded by the shared bootstrap module."
  type        = string
  default     = "7.7.7"
}

variable "argocd_timeout_seconds" {
  description = "Maximum seconds allowed for the initial ArgoCD bootstrap operations."
  type        = number
  default     = 600
}

variable "argocd" {
  description = "ArgoCD service and initial access configuration for the isolated dev cluster."
  type = object({
    service_type      = string
    loadbalancer_ip   = string
    hostname          = string
    insecure          = bool
    disable_auth      = bool
    anonymous_enabled = bool
    self_heal         = optional(bool, true)
  })
  default = {
    service_type      = "ClusterIP"
    loadbalancer_ip   = ""
    hostname          = ""
    insecure          = false
    disable_auth      = false
    anonymous_enabled = false
    self_heal         = true
  }

  validation {
    condition     = var.argocd.service_type == "ClusterIP"
    error_message = "The initial dev-k3s contract exposes ArgoCD only as ClusterIP."
  }
}
