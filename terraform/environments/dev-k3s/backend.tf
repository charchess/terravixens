terraform {
  # Development state is intentionally runner-local. It must remain on the Lab
  # VM that owns the K3d target and is excluded from Git.
  backend "local" {
    path = "state/terraform.tfstate"
  }
}
