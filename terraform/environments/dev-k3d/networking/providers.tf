terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
  }

  backend "local" {
    path = "state/terraform.tfstate"
  }
}

provider "helm" {
  kubernetes = { config_path = var.kubeconfig_path }
}

provider "kubectl" {
  config_path      = var.kubeconfig_path
  load_config_file = true
}
