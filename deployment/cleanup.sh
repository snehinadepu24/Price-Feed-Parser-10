#!/bin/bash
set -e

echo "🧹 Cleaning up AWS Stock Pipeline resources..."

# Confirm deletion
read -p "⚠️  This will DELETE ALL pipeline resources. Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

cd infra

# Get resource information before deletion
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
SCRIPT_BUCKET=$(terraform output -raw glue_scripts_bucket 2>/dev/null || echo "")
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")

# Empty S3 buckets first (required before Terraform can delete them)
if [ -n "$S3_BUCKET" ]; then
    echo "🗑️  Emptying S3 data bucket: $S3_BUCKET"
    aws s3 rm s3://$S3_BUCKET --recursive || echo "⚠️  Could not empty data bucket"
fi

if [ -n "$SCRIPT_BUCKET" ]; then
    echo "🗑️  Emptying S3 scripts bucket: $SCRIPT_BUCKET"
    aws s3 rm s3://$SCRIPT_BUCKET --recursive || echo "⚠️  Could not empty scripts bucket"
fi

# Delete ECR images
if [ -n "$ECR_REPO" ]; then
    REPO_NAME=$(echo $ECR_REPO | cut -d'/' -f2)
    echo "🗑️  Deleting ECR images in: $REPO_NAME"
    aws ecr batch-delete-image \
        --repository-name $REPO_NAME \
        --image-ids imageTag=latest || echo "⚠️  Could not delete ECR images"
fi

# Destroy Terraform resources
echo "🏗️  Destroying Terraform infrastructure..."
terraform destroy -auto-approve

echo "✅ Cleanup completed!"
echo ""
echo "📋 Manual cleanup (if needed):"
echo "1. Check CloudWatch log groups for any remaining logs"
echo "2. Verify S3 buckets are completely deleted"
echo "3. Check Secrets Manager for any remaining secrets"