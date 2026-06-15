output "buckets" {
  description = "Buckets criados no Garage"
  value = {
    cnpg_wal          = aws_s3_bucket.cnpg_wal.bucket
    clickhouse_backup = aws_s3_bucket.clickhouse_backup.bucket
    qdrant_snapshots  = aws_s3_bucket.qdrant_snapshots.bucket
    velero            = aws_s3_bucket.velero.bucket
    langfuse          = aws_s3_bucket.langfuse.bucket
  }
}
