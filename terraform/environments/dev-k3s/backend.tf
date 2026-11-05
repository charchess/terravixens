terraform {
  backend "s3" {
    bucket = "terraform-state-dev"
    key    = "k3s/terraform.tfstate"
    region = "us-east-1"

    # Credentials are provided only through AWS_ACCESS_KEY_ID and
    # AWS_SECRET_ACCESS_KEY in the Terraform process environment.
    endpoints = {
      s3 = "http://nas.truxonline.com:9000"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
