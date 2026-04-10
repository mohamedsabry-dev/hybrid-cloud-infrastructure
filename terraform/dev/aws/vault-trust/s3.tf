# S3 Bucket - etcd backup storage
# ================================

resource "aws_s3_bucket" "etcd_backup" {
  bucket = "hybrid-cloud-k8s-etcd-backup-dev"

  tags = {
    Name        = "etcd-backup"
    Environment = "Dev"
    Purpose     = "etcd backup storage"
    ManagedBy   = "Terraform"
  }
}
