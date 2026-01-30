terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
  }

  backend "s3" {
    bucket         = "hybrid-cloud-infrastructure-terraform-state"
    key            = "audit/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "hybrid-cloud-infrastructure-terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-west-2"
}

# 1. CloudWatch Log Group
resource "aws_cloudwatch_log_group" "test" {
  name              = "/test/audit-validation"
  retention_in_days = 1

  tags = {
    Name        = "Test-Audit-Logs"
    Environment = "Validation"
  }
}

# 2. CloudTrail (uses existing audit bucket)
resource "aws_cloudtrail" "test" {
  name           = "test-audit-trail"
  s3_bucket_name = "hybrid-cloud-infrastructure-audit-logs"

  tags = {
    Name        = "Test-Audit-Trail"
    Environment = "Validation"
  }
}

# 3. SNS Topic
resource "aws_sns_topic" "test" {
  name = "test-audit-alerts"

  tags = {
    Name        = "Test-Audit-Alerts"
    Environment = "Validation"
  }
}

# 4. CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "test" {
  alarm_name          = "test-audit-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TestMetric"
  namespace           = "Test/Audit"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Test alarm - delete after validation"
  alarm_actions       = [aws_sns_topic.test.arn]
}

# Outputs
output "log_group" {
  value = aws_cloudwatch_log_group.test.name
}

output "cloudtrail" {
  value = aws_cloudtrail.test.name
}

output "sns_topic" {
  value = aws_sns_topic.test.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.test.alarm_name
}
