# S3 Bucket - etcd backup storage
# ================================

resource "aws_s3_bucket" "etcd_backup" {
  bucket = "hybrid-cloud-k8s-etcd-backup-prod"

  tags = {
    Name        = "etcd-backup"
    Environment = "Prod"
    Purpose     = "etcd backup storage"
    ManagedBy   = "Terraform"
  }
}
