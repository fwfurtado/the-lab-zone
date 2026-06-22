output "buckets" {
  description = "Nome -> bucket_id dos buckets B2 gerenciados. O id ajuda a localizar/escopar a app key de backup no console do B2."
  value = {
    for name, b in b2_bucket.this : name => b.bucket_id
  }
}
