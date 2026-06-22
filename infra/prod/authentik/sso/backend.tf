terraform {
  backend "s3" {
    bucket = "the-lab-zone-tf-state"
    # CRÍTICO: key DIFERENTE da do vm/ (prod/authentik/terraform.tfstate).
    # Se repetir, os dois states se sobrescrevem no mesmo objeto do B2.
    key    = "prod/authentik/sso/terraform.tfstate"
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
