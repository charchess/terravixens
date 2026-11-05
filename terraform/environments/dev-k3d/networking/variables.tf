variable "kubeconfig_path" {
  type = string
}

variable "k8s_service_host" {
  type = string
}

variable "dns_upstreams" {
  description = "Reachable DNS resolvers used by CoreDNS on the K3d platform."
  type        = list(string)
  default     = ["192.168.200.69", "1.1.1.1"]

  validation {
    condition     = length(var.dns_upstreams) > 0
    error_message = "dns_upstreams must contain at least one reachable resolver."
  }
}

variable "cilium_chart_version" {
  type    = string
  default = "1.20.2"
}

variable "cilium_timeout_seconds" {
  type    = number
  default = 1200
}

variable "cilium_agent_capabilities" {
  type = object({ add = list(string), drop = list(string) })
  default = {
    add  = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
    drop = ["ALL"]
  }
}

variable "cilium_clean_capabilities" {
  type = object({ add = list(string), drop = list(string) })
  default = {
    add  = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
    drop = ["ALL"]
  }
}
