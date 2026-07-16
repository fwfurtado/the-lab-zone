terraform {
  backend "s3" {
    bucket = "the-lab-zone-tf-state"
    key    = "prod/garage/terraform.tfstate" # state separado do talos
    region = "us-east-005"
    endpoints = {
      s3 = "https://s3.us-east-005.backblazeb2.com"
    }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
