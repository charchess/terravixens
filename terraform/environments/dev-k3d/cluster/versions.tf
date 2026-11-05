terraform {
  required_version = ">= 1.5.0"

  required_providers {
    k3d = {
      source  = "SneakyBugs/k3d"
      version = "1.0.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "local" {
    path = "state/terraform.tfstate"
  }
}
