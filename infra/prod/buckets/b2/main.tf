resource "b2_bucket" "this" {
  for_each = var.buckets

  bucket_name = each.key
  bucket_type = "allPrivate"

  lifecycle_rules {
    file_name_prefix              = "" # aplica a todos os objetos do bucket
    days_from_uploading_to_hiding = each.value.retention_days
    days_from_hiding_to_deleting  = 1
  }

  # O backup é a tábua de salvação do tier-0: NUNCA destruir junto de um rebuild
  # da VM (e os módulos têm states separados justamente pra isso). Pra remover de
  # verdade, tire a entrada do map E este bloco, conscientemente.
  lifecycle {
    prevent_destroy = true
  }
}
