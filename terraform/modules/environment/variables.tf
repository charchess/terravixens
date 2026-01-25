# ============================================================================
# ENVIRONMENT MODULE - INPUT VARIABLES
# ============================================================================
# This module encapsulates the common logic for all environments (dev/test/staging/prod)
# Only environment-specific values differ via terraform.tfvars

# --------------------------------------------------------------------------
# ENVIRONMENT
# --------------------------------------------------------------------------
variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod"
  }
}

variable "git_branch" {
  description = "Git branch for ArgoCD targetRevision"
  type        = string
}

# --------------------------------------------------------------------------
# CLUSTER CONFIGURATION
# --------------------------------------------------------------------------
variable "cluster" {
  description = "Cluster global settings"
  type = object({
    name               = string
    endpoint           = string
    vip                = string
    talos_version      = string
    talos_image        = string
    kubernetes_version = string
  })
}

# --------------------------------------------------------------------------
# NODES CONFIGURATION
# --------------------------------------------------------------------------
variable "control_plane_nodes" {
  description = "Control plane nodes configuration"
  type = map(object({
    name         = string
    ip_address   = string
    mac_address  = string
    install_disk = string
    nameservers  = optional(list(string), [])
    network = object({
      interface = string
      vlans = list(object({
        vlanId    = number
        addresses = list(string)
        gateway   = string
      }))
    })
  }))

  validation {
    condition     = length(var.control_plane_nodes) % 2 == 1
    error_message = "Control plane nodes must be an odd number (1, 3, 5) for etcd quorum"
  }
}

variable "worker_nodes" {
  description = "Worker nodes configuration (optional)"
  type = map(object({
    name         = string
    ip_address   = string
    mac_address  = string
    install_disk = string
    nameservers  = optional(list(string), [])
    network = object({
      interface = string
      vlans = list(object({
        vlanId    = number
        addresses = list(string)
        gateway   = string
      }))
    })
  }))
  default = {}
}

# --------------------------------------------------------------------------
# ARGOCD CONFIGURATION
# --------------------------------------------------------------------------
variable "argocd" {
  description = "ArgoCD configuration"
  type = object({
    service_type      = string
    loadbalancer_ip   = string
    hostname          = string
    insecure          = bool
    disable_auth      = bool
    anonymous_enabled = bool
  })

  validation {
    condition     = contains(["LoadBalancer", "ClusterIP", "NodePort"], var.argocd.service_type)
    error_message = "ArgoCD service type must be LoadBalancer, ClusterIP, or NodePort"
  }

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.argocd.loadbalancer_ip))
    error_message = "ArgoCD LoadBalancer IP must be a valid IPv4 address"
  }
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
variable "paths" {
  description = "File paths for generated configurations"
  type = object({
    kubeconfig       = string
    talosconfig      = string
    infisical_secret = string
  })
}
