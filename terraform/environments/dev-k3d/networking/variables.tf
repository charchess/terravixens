variable "kubeconfig_path" {
  type = string
}

variable "k8s_service_host" {
  type = string
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
