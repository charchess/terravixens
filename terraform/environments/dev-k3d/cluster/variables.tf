variable "cluster_name" {
  description = "K3d cluster name owned by this Terraform root."
  type        = string
  default     = "vixens-dev"
}

variable "servers" {
  description = "Number of K3d server nodes."
  type        = number
  default     = 1
}

variable "agents" {
  description = "Number of K3d agent nodes."
  type        = number
  default     = 1
}

variable "k3s_image" {
  description = "Pinned K3s image used by K3d."
  type        = string
  default     = "rancher/k3s:v1.35.5-k3s1"
}

variable "api_host_port" {
  description = "Loopback-only host port for the K3d Kubernetes API."
  type        = number
  default     = 6445
}

variable "kubeconfig_path" {
  description = "Protected runner-local path written with the generated kubeconfig."
  type        = string
}
