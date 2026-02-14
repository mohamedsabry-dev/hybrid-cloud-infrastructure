# Define the Limited Policy
resource "aws_iam_policy" "tf_management_policy" {
  name        = "TerraformStateManagement"
  description = "Allows management of TF state in S3 and locking in DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permissions for S3 State Bucket
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        # Permissions for DynamoDB Locking
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_state_lock.arn
      }
    ]
  })
}