#!/bin/bash
set -e

echo "🔧 Setting up Terraform Backend Infrastructure..."

# Get user inputs
read -p "Enter your AWS region (default: ap-south-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-south-1}

read -p "Enter a unique suffix for your Terraform state bucket (e.g., your-initials-123): " BUCKET_SUFFIX

if [ -z "$BUCKET_SUFFIX" ]; then
    echo "❌ Bucket suffix is required for uniqueness"
    exit 1
fi

BUCKET_NAME="stock-pipeline-terraform-state-${BUCKET_SUFFIX}"
DYNAMODB_TABLE="terraform-state-lock-${BUCKET_SUFFIX}"

echo "🪣 Creating S3 bucket: $BUCKET_NAME"
echo "🔒 Creating DynamoDB table: $DYNAMODB_TABLE"

# Create S3 bucket for Terraform state
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

# Block public access
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $AWS_REGION

echo "✅ Backend infrastructure created successfully!"
echo ""
echo "📝 Update your main.tf backend configuration with:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"$BUCKET_NAME\""
echo "    key            = \"stock-pipeline/terraform.tfstate\""
echo "    region         = \"$AWS_REGION\""
echo "    encrypt        = true"
echo "    dynamodb_table = \"$DYNAMODB_TABLE\""
echo "  }"
echo "}"
echo ""
echo "🚀 Now you can run 'terraform init' and 'terraform apply'"
