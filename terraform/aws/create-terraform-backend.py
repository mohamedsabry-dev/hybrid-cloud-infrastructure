#!/usr/bin/env python3
"""
Terraform Backend Infrastructure Setup
Creates S3 bucket and DynamoDB table for Terraform state management
Designed to run in AWS CloudShell with interactive prompts
"""

import boto3
import sys
from botocore.exceptions import ClientError

# Configuration
BUCKET_NAME = "hybrid-cloud-infrastructure-terraform-state"
TABLE_NAME = "hybrid-cloud-infrastructure-terraform-state-lock"
REGION = "eu-west-2"

# Initialize AWS clients
s3 = boto3.client('s3', region_name=REGION)
dynamodb = boto3.client('dynamodb', region_name=REGION)

def check_s3_bucket():
    """Check if S3 bucket exists"""
    try:
        s3.head_bucket(Bucket=BUCKET_NAME)
        return True
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == '404':
            return False
        else:
            print(f"❌ Error checking bucket: {e}")
            return None

def check_dynamodb_table():
    """Check if DynamoDB table exists"""
    try:
        dynamodb.describe_table(TableName=TABLE_NAME)
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            return False
        else:
            print(f"❌ Error checking table: {e}")
            return None

def create_s3_bucket():
    """Create S3 bucket with versioning and encryption"""
    try:
        print(f"\n📦 Creating S3 bucket: {BUCKET_NAME}")
        print(f"   Region: {REGION}")
        print(f"   Versioning: Enabled")
        print(f"   Encryption: Enabled (SSE-S3)")
        print(f"   Public Access: Blocked")
        
        response = input("\n   Proceed with S3 bucket creation? (yes/no): ")
        if response.lower() != 'yes':
            print("   ⏭️  Skipped S3 bucket creation")
            return False
        
        # Create bucket with region constraint
        s3.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={'LocationConstraint': REGION}
        )
        print("   ✅ Bucket created")
        
        # Enable versioning
        s3.put_bucket_versioning(
            Bucket=BUCKET_NAME,
            VersioningConfiguration={'Status': 'Enabled'}
        )
        print("   ✅ Versioning enabled")
        
        # Enable encryption
        s3.put_bucket_encryption(
            Bucket=BUCKET_NAME,
            ServerSideEncryptionConfiguration={
                'Rules': [{
                    'ApplyServerSideEncryptionByDefault': {
                        'SSEAlgorithm': 'AES256'
                    },
                    'BucketKeyEnabled': True
                }]
            }
        )
        print("   ✅ Encryption enabled")
        
        # Block public access
        s3.put_public_access_block(
            Bucket=BUCKET_NAME,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        print("   ✅ Public access blocked")
        
        # Add tags
        s3.put_bucket_tagging(
            Bucket=BUCKET_NAME,
            Tagging={
                'TagSet': [
                    {'Key': 'Project', 'Value': 'hybrid-cloud-infrastructure'},
                    {'Key': 'Purpose', 'Value': 'TerraformState'},
                    {'Key': 'ManagedBy', 'Value': 'PythonScript'}
                ]
            }
        )
        print("   ✅ Tags applied")
        
        print(f"\n✅ S3 bucket '{BUCKET_NAME}' created successfully!")
        return True
        
    except ClientError as e:
        print(f"\n❌ Failed to create S3 bucket: {e}")
        return False

def create_dynamodb_table():
    """Create DynamoDB table for state locking"""
    try:
        print(f"\n🔒 Creating DynamoDB table: {TABLE_NAME}")
        print(f"   Region: {REGION}")
        print(f"   Partition Key: LockID (String)")
        print(f"   Billing Mode: On-Demand")
        
        response = input("\n   Proceed with DynamoDB table creation? (yes/no): ")
        if response.lower() != 'yes':
            print("   ⏭️  Skipped DynamoDB table creation")
            return False
        
        # Create table
        dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[
                {'AttributeName': 'LockID', 'KeyType': 'HASH'}
            ],
            AttributeDefinitions=[
                {'AttributeName': 'LockID', 'AttributeType': 'S'}
            ],
            BillingMode='PAY_PER_REQUEST',
            Tags=[
                {'Key': 'Project', 'Value': 'hybrid-cloud-infrastructure'},
                {'Key': 'Purpose', 'Value': 'TerraformStateLocking'},
                {'Key': 'ManagedBy', 'Value': 'PythonScript'}
            ]
        )
        print("   ✅ Table creation initiated")
        
        # Wait for table to be active
        print("   ⏳ Waiting for table to become active (this may take 30 seconds)...")
        waiter = dynamodb.get_waiter('table_exists')
        waiter.wait(TableName=TABLE_NAME)
        print("   ✅ Table is now active")
        
        print(f"\n✅ DynamoDB table '{TABLE_NAME}' created successfully!")
        return True
        
    except ClientError as e:
        print(f"\n❌ Failed to create DynamoDB table: {e}")
        return False

def update_s3_settings():
    """Update existing S3 bucket settings"""
    try:
        print(f"\n🔧 Updating S3 bucket settings: {BUCKET_NAME}")
        
        response = input("   Apply recommended settings? (yes/no): ")
        if response.lower() != 'yes':
            print("   ⏭️  Skipped S3 updates")
            return False
        
        # Enable versioning (idempotent)
        s3.put_bucket_versioning(
            Bucket=BUCKET_NAME,
            VersioningConfiguration={'Status': 'Enabled'}
        )
        print("   ✅ Versioning verified/enabled")
        
        # Enable encryption (idempotent)
        s3.put_bucket_encryption(
            Bucket=BUCKET_NAME,
            ServerSideEncryptionConfiguration={
                'Rules': [{
                    'ApplyServerSideEncryptionByDefault': {
                        'SSEAlgorithm': 'AES256'
                    },
                    'BucketKeyEnabled': True
                }]
            }
        )
        print("   ✅ Encryption verified/enabled")
        
        # Block public access (idempotent)
        s3.put_public_access_block(
            Bucket=BUCKET_NAME,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        print("   ✅ Public access blocked verified")
        
        print(f"\n✅ S3 bucket settings updated!")
        return True
        
    except ClientError as e:
        print(f"\n❌ Failed to update S3 settings: {e}")
        return False

def main():
    print("=" * 70)
    print("  Terraform Backend Infrastructure Setup")
    print("=" * 70)
    print(f"\nConfiguration:")
    print(f"  AWS Region: {REGION}")
    print(f"  S3 Bucket: {BUCKET_NAME}")
    print(f"  DynamoDB Table: {TABLE_NAME}")
    print("\n" + "=" * 70)
    
    # Check current state
    print("\n🔍 Checking existing resources...")
    
    bucket_exists = check_s3_bucket()
    if bucket_exists is None:
        print("❌ Unable to verify S3 bucket status. Exiting.")
        sys.exit(1)
    
    table_exists = check_dynamodb_table()
    if table_exists is None:
        print("❌ Unable to verify DynamoDB table status. Exiting.")
        sys.exit(1)
    
    # Report status
    print(f"\n📊 Current Status:")
    print(f"  S3 Bucket: {'✅ EXISTS' if bucket_exists else '❌ NOT FOUND'}")
    print(f"  DynamoDB Table: {'✅ EXISTS' if table_exists else '❌ NOT FOUND'}")
    
    # Determine actions
    if bucket_exists and table_exists:
        print("\n✅ Both resources already exist!")
        response = input("\nWould you like to update S3 bucket settings? (yes/no): ")
        if response.lower() == 'yes':
            update_s3_settings()
        else:
            print("\n✅ No changes made. Infrastructure is ready!")
        sys.exit(0)
    
    # Create missing resources
    print("\n" + "=" * 70)
    print("  Resources to Create")
    print("=" * 70)
    
    if not bucket_exists:
        if not create_s3_bucket():
            print("\n❌ S3 bucket creation failed. Exiting.")
            sys.exit(1)
    else:
        print(f"\nℹ️  S3 bucket already exists, skipping creation")
    
    if not table_exists:
        if not create_dynamodb_table():
            print("\n❌ DynamoDB table creation failed.")
            if not bucket_exists:  # We just created the bucket
                response = input("\nDelete the S3 bucket we just created? (yes/no): ")
                if response.lower() == 'yes':
                    try:
                        s3.delete_bucket(Bucket=BUCKET_NAME)
                        print(f"✅ Cleaned up S3 bucket: {BUCKET_NAME}")
                    except:
                        print(f"⚠️  Could not delete bucket (may have objects)")
            sys.exit(1)
    else:
        print(f"\nℹ️  DynamoDB table already exists, skipping creation")
    
    # Success summary
    print("\n" + "=" * 70)
    print("  ✅ Setup Complete!")
    print("=" * 70)
    print(f"\nTerraform Backend Configuration:")
    print(f"""
terraform {{
  backend "s3" {{
    bucket         = "{BUCKET_NAME}"
    key            = "path/to/terraform.tfstate"
    region         = "{REGION}"
    dynamodb_table = "{TABLE_NAME}"
    encrypt        = true
  }}
}}
""")
    print("=" * 70)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Script interrupted by user. Exiting...")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ Unexpected error: {e}")
        sys.exit(1)
