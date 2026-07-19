output "buckets" {
  description = "Buckets criados no Garage"
  value = {
    cnpg_wal          = aws_s3_bucket.cnpg_wal.bucket
    clickhouse_backup = aws_s3_bucket.clickhouse_backup.bucket
    qdrant_snapshots  = aws_s3_bucket.qdrant_snapshots.bucket
    velero            = aws_s3_bucket.velero.bucket
    langfuse          = aws_s3_bucket.langfuse.bucket
    argo_workflows    = aws_s3_bucket.argo_workflows.bucket
    triage_reports    = aws_s3_bucket.triages.bucket
    tempo             = aws_s3_bucket.tempo.bucket
    pyroscope         = aws_s3_bucket.pyroscope.bucket
    lakehouse         = aws_s3_bucket.lakehouse.bucket
  }
}
