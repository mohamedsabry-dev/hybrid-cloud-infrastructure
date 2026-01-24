## Bootstrap Terraform AWS Provider Configuration and Connection Tests
## Linear Issue: INFRA-291 ##

# Steps: 
# // 1. Decalre AWS Provider Version
# // 2. Configure AWS Provider with Region 
# // 3. Use Data Sources to :
# //    - Check AWS Caller Identity (to verify credentials)
# //    - List S3 Buckets (to verify read access)
# //    - Test IAM Permissions (to verify access to specific users)
# //    - List DynamoDB Tables (to verify read access) 
# //    - List EC2 Instances (to verify no access)
# //    - List IAM Users (to verify no access)
# // 4. Output Results
