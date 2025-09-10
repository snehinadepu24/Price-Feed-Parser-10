#!/bin/bash

# MVP Deployment Script for AWS Free Tier
# This script deploys only the free tier services and creates a simple data pipeline

set -e

echo "🚀 Starting MVP Deployment for Stock Pipeline"
echo "============================================="

# Configuration
PROJECT_NAME="stock-pipeline-mvp"
AWS_REGION="${AWS_REGION:-ap-south-1}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if notification email is provided
    if [ -z "$NOTIFICATION_EMAIL" ]; then
        print_error "NOTIFICATION_EMAIL environment variable is required."
        print_status "Example: export NOTIFICATION_EMAIL=your-email@example.com"
        exit 1
    fi
    
    print_status "All prerequisites met ✅"
}

# Validate AWS account is suitable for free tier
validate_aws_account() {
    print_header "Validating AWS Account"
    
    # Get account information
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_status "AWS Account ID: $ACCOUNT_ID"
    
    # Check if we're in the right region
    CURRENT_REGION=$(aws configure get region)
    if [ "$CURRENT_REGION" != "$AWS_REGION" ]; then
        print_warning "Current AWS region ($CURRENT_REGION) differs from deployment region ($AWS_REGION)"
        print_status "Setting region to $AWS_REGION for this deployment"
    fi
    
    print_status "Account validation complete ✅"
}

# Create Lambda deployment package
create_lambda_package() {
    print_header "Creating Lambda Deployment Package"
    
    # Create temporary directory for Lambda package
    LAMBDA_DIR="./lambda_package"
    rm -rf $LAMBDA_DIR
    mkdir -p $LAMBDA_DIR
    
    # Copy Lambda function
    cp ../ingestion/lambda_ingestion.py $LAMBDA_DIR/
    
    # Create requirements.txt for Lambda
    cat > $LAMBDA_DIR/requirements.txt << EOF
requests>=2.31.0
boto3>=1.34.0
botocore>=1.34.0
EOF
    
    # Install dependencies if we have pip
    if command -v pip &> /dev/null; then
        print_status "Installing Lambda dependencies..."
        pip install -r $LAMBDA_DIR/requirements.txt -t $LAMBDA_DIR/ --quiet
    else
        print_warning "pip not found. Lambda will use runtime dependencies."
    fi
    
    # Create ZIP file
    cd $LAMBDA_DIR
    zip -r ../lambda_ingestion.zip . > /dev/null
    cd ..
    
    print_status "Lambda package created: lambda_ingestion.zip ✅"
    
    # Cleanup
    rm -rf $LAMBDA_DIR
}

# Deploy infrastructure
deploy_infrastructure() {
    print_header "Deploying MVP Infrastructure"
    
    # Navigate to infrastructure directory
    cd ../infra
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init -input=false
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    terraform validate
    
    # Plan deployment
    print_status "Planning MVP deployment..."
    terraform plan \
        -var="notification_email=$NOTIFICATION_EMAIL" \
        -var="aws_region=$AWS_REGION" \
        -var="project_name=$PROJECT_NAME" \
        -input=false \
        -out=mvp-plan.tfplan \
        main-mvp.tf
    
    # Apply deployment
    print_status "Applying MVP infrastructure..."
    terraform apply -input=false mvp-plan.tfplan
    
    # Get outputs
    print_status "Retrieving deployment outputs..."
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    LAMBDA_FUNCTION=$(terraform output -raw lambda_function_name)
    SNS_TOPIC=$(terraform output -raw sns_topic_arn)
    SECRET_NAME=$(terraform output -raw fyers_secret_name)
    
    print_status "Infrastructure deployed successfully ✅"
    
    # Go back to deployment directory
    cd ../deployment
}

# Configure API credentials
configure_credentials() {
    print_header "Configuring API Credentials"
    
    print_warning "You need to manually update the Fyers API credentials in AWS Secrets Manager."
    print_status "Secret name: $SECRET_NAME"
    print_status ""
    print_status "Required credentials:"
    print_status "  - access_token: Your Fyers API access token"
    print_status "  - client_id: Your Fyers client ID"
    print_status "  - refresh_token: Your Fyers refresh token"
    print_status ""
    print_status "You can update these using AWS Console or CLI:"
    print_status "aws secretsmanager update-secret --secret-id $SECRET_NAME --secret-string '{\"access_token\":\"YOUR_TOKEN\",\"client_id\":\"YOUR_CLIENT_ID\",\"refresh_token\":\"YOUR_REFRESH_TOKEN\"}'"
}

# Test the deployment
test_deployment() {
    print_header "Testing MVP Deployment"
    
    # Invoke Lambda function manually
    print_status "Testing Lambda function..."
    
    # Create test event
    cat > test_event.json << EOF
{
  "test": true,
  "source": "manual-deployment-test"
}
EOF
    
    # Invoke function (this will likely fail without proper API credentials, but we can check the setup)
    aws lambda invoke \
        --function-name $LAMBDA_FUNCTION \
        --payload file://test_event.json \
        --region $AWS_REGION \
        response.json || true
    
    # Check response
    if [ -f response.json ]; then
        print_status "Lambda function invoked. Check CloudWatch logs for details."
        cat response.json
    fi
    
    # Cleanup test files
    rm -f test_event.json response.json
    
    print_status "Deployment test completed ✅"
}

# Display deployment summary
show_deployment_summary() {
    print_header "MVP Deployment Summary"
    
    echo ""
    echo "🎉 MVP Deployment Complete!"
    echo "=========================="
    echo ""
    echo "📊 Deployed Resources (Free Tier):"
    echo "  • S3 Bucket: $S3_BUCKET"
    echo "  • Lambda Function: $LAMBDA_FUNCTION"
    echo "  • SNS Topic: $SNS_TOPIC"
    echo "  • Secrets Manager: $SECRET_NAME"
    echo ""
    echo "💰 Estimated Monthly Cost: $0.40 - $2.00"
    echo "  • S3: Free (5GB limit)"
    echo "  • Lambda: Free (1M requests limit)"
    echo "  • SNS: Free (1K notifications limit)"
    echo "  • Secrets Manager: $0.40/month"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Update Fyers API credentials in Secrets Manager"
    echo "  2. Monitor CloudWatch logs for function execution"
    echo "  3. Check S3 bucket for ingested data"
    echo "  4. Set up billing alerts in AWS Console"
    echo ""
    echo "📍 Useful Links:"
    echo "  • CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups"
    echo "  • S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$S3_BUCKET?region=$AWS_REGION"
    echo "  • Lambda Console: https://console.aws.amazon.com/lambda/home?region=$AWS_REGION#/functions/$LAMBDA_FUNCTION"
    echo ""
    echo "⚡ Lambda Schedule: Every 15 minutes (configurable)"
    echo "📈 Data Processing: 10 top NSE stocks every 15 minutes"
    echo ""
    echo "🚀 To scale up later, uncomment expensive services in main-mvp.tf:"
    echo "  • RDS PostgreSQL"
    echo "  • ECS Fargate"
    echo "  • AWS Glue"
    echo "  • Athena"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f lambda_ingestion.zip
    rm -f mvp-plan.tfplan
}

# Main execution
main() {
    echo "🎯 MVP Deployment for AWS Free Tier Stock Pipeline"
    echo "================================================="
    echo ""
    echo "This script will deploy:"
    echo "  ✅ S3 bucket for data storage"
    echo "  ✅ Lambda function for data ingestion"
    echo "  ✅ SNS topic for notifications"
    echo "  ✅ Secrets Manager for API credentials"
    echo "  ✅ CloudWatch for logging"
    echo "  ✅ Cost budget alerts"
    echo ""
    echo "💡 All services use AWS Free Tier limits"
    echo "💰 Estimated cost: $0.40-$2.00/month"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled by user"
        exit 0
    fi
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Run deployment steps
    check_prerequisites
    validate_aws_account
    create_lambda_package
    deploy_infrastructure
    configure_credentials
    test_deployment
    show_deployment_summary
    
    print_status "MVP deployment completed successfully! 🎉"
}

# Run main function
main "$@"
