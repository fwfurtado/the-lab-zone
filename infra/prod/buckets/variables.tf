variable "garage_endpoint" {
  description = "Garage S3 API endpoint (interno ao cluster)"
  type        = string
  default     = "https://s3.lab.the-lab.zone"
}

variable "garage_access_key" {
  description = "Garage access key com permissão de criar buckets"
  type        = string
  sensitive   = true
}

variable "garage_secret_key" {
  description = "Garage secret key"
  type        = string
  sensitive   = true
}
