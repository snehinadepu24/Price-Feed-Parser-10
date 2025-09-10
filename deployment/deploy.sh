#!/bin/bash
sread -p "Enter AWS region (default: ap-south-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-south-1} -e

# AWS Stock Pipeline Deployment Script
echo "🚀 Starting AWS Stock Pipeline Deployment..."

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Aborting." >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }

# Get user inputs
read -p "Enter your notification email: " NOTIFICATION_EMAIL
read -p "Enter AWS region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

echo "📧 Notification email: $NOTIFICATION_EMAIL"
echo "🌍 AWS region: $AWS_REGION"

# Step 1: Deploy Infrastructure
echo "🏗️  Step 1: Deploying infrastructure with Terraform..."
cd infra
terraform init
terraform plan -var="notification_email=$NOTIFICATION_EMAIL" -var="aws_region=$AWS_REGION"
terraform apply -var="notification_email=$NOTIFICATION_EMAIL" -var="aws_region=$AWS_REGION" -auto-approve

# Get outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
SCRIPT_BUCKET=$(terraform output -raw glue_scripts_bucket || echo "")
FYERS_SECRET=$(terraform output -raw fyers_secret_name || echo "")
RDS_SECRET=$(terraform output -raw rds_secret_name || echo "")

echo "✅ Infrastructure deployed successfully!"

# Step 2: Build and Push Container
echo "🐳 Step 2: Building and pushing container to ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push
cd ../
docker build -t stock-pipeline-ingestion ./ingestion/
docker tag stock-pipeline-ingestion:latest $ECR_URL:latest
docker push $ECR_URL:latest

echo "✅ Container pushed to ECR successfully!"

# Step 3: Upload Glue Script
echo "📄 Step 3: Uploading Glue ETL script..."
if [ -n "$SCRIPT_BUCKET" ]; then
    aws s3 cp etl/glue_job.py s3://$SCRIPT_BUCKET/etl/glue_job.py
    echo "✅ Glue script uploaded successfully!"
else
    echo "⚠️  Could not find Glue scripts bucket. Please upload manually."
fi

# Step 4: Setup Database Schema
echo "🗄️  Step 4: Setting up database schema..."
if command -v psql >/dev/null 2>&1; then
    if [ -n "$RDS_SECRET" ]; then
        echo "Getting RDS credentials from Secrets Manager..."
        RDS_CREDS=$(aws secretsmanager get-secret-value --secret-id $RDS_SECRET --query SecretString --output text)
        
        DB_HOST=$(echo $RDS_CREDS | jq -r '.host')
        DB_USER=$(echo $RDS_CREDS | jq -r '.username')
        DB_PASS=$(echo $RDS_CREDS | jq -r '.password')
        DB_NAME=$(echo $RDS_CREDS | jq -r '.dbname')
        
        echo "Executing database schema for AWS RDS PostgreSQL..."
        PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f sql/rds_schema.sql
        echo "✅ AWS RDS PostgreSQL schema created successfully!"
    else
        echo "⚠️  Could not find RDS secret. Please setup database manually."
    fi
else
    echo "⚠️  psql not found. Please install PostgreSQL client and run sql/rds_schema.sql manually."
fi

# Step 5: Configure API Credentials
echo "🔐 Step 5: Configure Fyers API credentials..."
if [ -n "$FYERS_SECRET" ]; then
    echo ""
    echo "⚠️  IMPORTANT: You need to update Fyers API credentials manually:"
    echo "aws secretsmanager update-secret \\"
    echo "  --secret-id $FYERS_SECRET \\"
    echo "  --secret-string '{"
    echo "    \"access_token\": \"YOUR_FYERS_ACCESS_TOKEN\","
    echo "    \"refresh_token\": \"YOUR_FYERS_REFRESH_TOKEN\","
    echo "    \"client_id\": \"YOUR_FYERS_CLIENT_ID\""
    echo "  }'"
    echo ""
fi

echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Update Fyers API credentials in Secrets Manager (see command above)"
echo "2. The pipeline will start ingesting data automatically every 5 minutes"
echo "3. ETL processing runs daily at 2:00 AM UTC"
echo "4. Monitor the pipeline through CloudWatch logs and SNS notifications"
echo ""
echo "🔍 Useful Commands:"
echo "# Check ECS task logs:"
echo "aws logs tail /ecs/stock-pipeline-ingestion --follow"
echo ""
echo "# Check S3 data:"
echo "aws s3 ls s3://$(terraform output -raw s3_bucket_name)/raw/ --recursive"
echo ""
echo "# Test Athena query:"
echo "# Go to AWS Console > Athena and run queries from README.md"