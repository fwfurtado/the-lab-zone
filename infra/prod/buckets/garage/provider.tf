terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


provider "aws" {
  # Credenciais do Garage (access key com permissão de criar buckets)
  access_key = var.garage_access_key
  secret_key = var.garage_secret_key
  region     = "garage"

  # Aponta para o Garage interno
  endpoints {
    s3 = var.garage_endpoint
  }

  # Necessário para S3-compatible não-AWS
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true
}
