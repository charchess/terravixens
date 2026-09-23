terraform {
  backend "s3" {
    bucket = "terraform-state-prod"
    key    = "terraform.tfstate"
    region = "us-east-1"

    # VersityGW on TrueNAS. Credentials are injected at runtime from OpenBao.
    endpoints = {
      s3 = "http://nas.truxonline.com:30157"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
