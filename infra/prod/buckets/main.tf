# ── Buckets ────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "cnpg_wal" {
  bucket = "cnpg-wal"
}

resource "aws_s3_bucket" "clickhouse_backup" {
  bucket = "clickhouse-backup"
}

resource "aws_s3_bucket" "qdrant_snapshots" {
  bucket = "qdrant-snapshots"
}

resource "aws_s3_bucket" "velero" {
  bucket = "velero"
}

resource "aws_s3_bucket" "langfuse" {
  bucket = "langfuse"
}
