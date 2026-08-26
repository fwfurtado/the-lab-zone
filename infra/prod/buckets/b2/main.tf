resource "b2_bucket" "this" {
  for_each = var.buckets

  bucket_name = each.key
  bucket_type = "allPrivate"

  dynamic "lifecycle_rules" {
    for_each = each.value.lifecycle_rules
    content {
      file_name_prefix              = lifecycle_rules.value.prefix
      days_from_uploading_to_hiding = lifecycle_rules.value.retention_days
      days_from_hiding_to_deleting  = 1
    }
  }

  # O backup é a tábua de salvação do tier-0: NUNCA destruir junto de um rebuild
  # da VM (e os módulos têm states separados justamente pra isso). Pra remover de
  # verdade, tire a entrada do map E este bloco, conscientemente.
  lifecycle {
    prevent_destroy = true
  }
}
