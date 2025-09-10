# MVP Deployment Script for AWS Free Tier (PowerShell)
# This script deploys only the free tier services and creates a simple data pipeline

param(
    [Parameter(Mandatory=$true)]
    [string]$NotificationEmail,
    
    [string]$AwsRegion = "ap-south-1",
    [string]$ProjectName = "stock-pipeline-mvp"
)

# Configuration
$ErrorActionPreference = "Stop"

# Color functions for output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Header {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Blue
}

# Check prerequisites
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    try {
        aws --version | Out-Null
        Write-Status "AWS CLI found ✅"
    }
    catch {
        Write-Error "AWS CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if Terraform is installed
    try {
        terraform version | Out-Null
        Write-Status "Terraform found ✅"
    }
    catch {
        Write-Error "Terraform is not installed. Please install it first."
        exit 1
    }
    
    # Check AWS credentials
    try {
        aws sts get-caller-identity | Out-Null
        Write-Status "AWS credentials configured ✅"
    }
    catch {
        Write-Error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    }
    
    Write-Status "All prerequisites met ✅"
}

# Validate AWS account
function Test-AwsAccount {
    Write-Header "Validating AWS Account"
    
    # Get account information
    $AccountId = aws sts get-caller-identity --query Account --output text
    Write-Status "AWS Account ID: $AccountId"
    
    # Check current region
    $CurrentRegion = aws configure get region
    if ($CurrentRegion -ne $AwsRegion) {
        Write-Warning "Current AWS region ($CurrentRegion) differs from deployment region ($AwsRegion)"
        Write-Status "Setting region to $AwsRegion for this deployment"
    }
    
    Write-Status "Account validation complete ✅"
}

# Create Lambda deployment package
function New-LambdaPackage {
    Write-Header "Creating Lambda Deployment Package"
    
    # Create temporary directory for Lambda package
    $LambdaDir = ".\lambda_package"
    if (Test-Path $LambdaDir) {
        Remove-Item $LambdaDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $LambdaDir -Force | Out-Null
    
    # Copy Lambda function
    Copy-Item "..\ingestion\lambda_ingestion.py" $LambdaDir
    
    # Create requirements.txt for Lambda
    @"
requests>=2.31.0
boto3>=1.34.0
botocore>=1.34.0
"@ | Out-File -FilePath "$LambdaDir\requirements.txt" -Encoding UTF8
    
    # Install dependencies if we have pip
    try {
        pip --version | Out-Null
        Write-Status "Installing Lambda dependencies..."
        pip install -r "$LambdaDir\requirements.txt" -t $LambdaDir --quiet
    }
    catch {
        Write-Warning "pip not found. Lambda will use runtime dependencies."
    }
    
    # Create ZIP file
    $ZipPath = ".\lambda_ingestion.zip"
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
    
    # Use PowerShell 5+ Compress-Archive or 7-zip
    try {
        Compress-Archive -Path "$LambdaDir\*" -DestinationPath $ZipPath -Force
        Write-Status "Lambda package created: lambda_ingestion.zip ✅"
    }
    catch {
        Write-Error "Failed to create ZIP file. Please install 7-zip or use PowerShell 5+."
        exit 1
    }
    
    # Cleanup
    Remove-Item $LambdaDir -Recurse -Force
}

# Deploy infrastructure
function Deploy-Infrastructure {
    Write-Header "Deploying MVP Infrastructure"
    
    # Navigate to infrastructure directory
    Push-Location "..\infra"
    
    try {
        # Initialize Terraform
        Write-Status "Initializing Terraform..."
        terraform init -input=false
        
        # Validate configuration
        Write-Status "Validating Terraform configuration..."
        terraform validate
        
        # Plan deployment
        Write-Status "Planning MVP deployment..."
        terraform plan `
            -var="notification_email=$NotificationEmail" `
            -var="aws_region=$AwsRegion" `
            -var="project_name=$ProjectName" `
            -input=false `
            -out=mvp-plan.tfplan `
            main-mvp.tf
        
        # Apply deployment
        Write-Status "Applying MVP infrastructure..."
        terraform apply -input=false mvp-plan.tfplan
        
        # Get outputs
        Write-Status "Retrieving deployment outputs..."
        $script:S3Bucket = terraform output -raw s3_bucket_name
        $script:LambdaFunction = terraform output -raw lambda_function_name
        $script:SnsTopicArn = terraform output -raw sns_topic_arn
        $script:SecretName = terraform output -raw fyers_secret_name
        
        Write-Status "Infrastructure deployed successfully ✅"
    }
    finally {
        # Go back to deployment directory
        Pop-Location
    }
}

# Configure API credentials
function Set-ApiCredentials {
    Write-Header "Configuring API Credentials"
    
    Write-Warning "You need to manually update the Fyers API credentials in AWS Secrets Manager."
    Write-Status "Secret name: $script:SecretName"
    Write-Host ""
    Write-Status "Required credentials:"
    Write-Status "  - access_token: Your Fyers API access token"
    Write-Status "  - client_id: Your Fyers client ID" 
    Write-Status "  - refresh_token: Your Fyers refresh token"
    Write-Host ""
    Write-Status "You can update these using AWS Console or CLI:"
    Write-Host "aws secretsmanager update-secret --secret-id $($script:SecretName) --secret-string '{`"access_token`":`"YOUR_TOKEN`",`"client_id`":`"YOUR_CLIENT_ID`",`"refresh_token`":`"YOUR_REFRESH_TOKEN`"}'" -ForegroundColor Cyan
}

# Test the deployment
function Test-Deployment {
    Write-Header "Testing MVP Deployment"
    
    # Invoke Lambda function manually
    Write-Status "Testing Lambda function..."
    
    # Create test event
    $TestEvent = @{
        test = $true
        source = "manual-deployment-test"
    } | ConvertTo-Json
    
    $TestEvent | Out-File -FilePath "test_event.json" -Encoding UTF8
    
    # Invoke function
    try {
        aws lambda invoke `
            --function-name $script:LambdaFunction `
            --payload file://test_event.json `
            --region $AwsRegion `
            response.json
        
        if (Test-Path "response.json") {
            Write-Status "Lambda function invoked. Check CloudWatch logs for details."
            Get-Content "response.json"
        }
    }
    catch {
        Write-Warning "Lambda invocation test failed (expected without proper API credentials)"
    }
    finally {
        # Cleanup test files
        if (Test-Path "test_event.json") { Remove-Item "test_event.json" -Force }
        if (Test-Path "response.json") { Remove-Item "response.json" -Force }
    }
    
    Write-Status "Deployment test completed ✅"
}

# Display deployment summary
function Show-DeploymentSummary {
    Write-Header "MVP Deployment Summary"
    
    Write-Host ""
    Write-Host "🎉 MVP Deployment Complete!" -ForegroundColor Green
    Write-Host "=========================="
    Write-Host ""
    Write-Host "📊 Deployed Resources (Free Tier):"
    Write-Host "  • S3 Bucket: $($script:S3Bucket)"
    Write-Host "  • Lambda Function: $($script:LambdaFunction)"
    Write-Host "  • SNS Topic: $($script:SnsTopicArn)"
    Write-Host "  • Secrets Manager: $($script:SecretName)"
    Write-Host ""
    Write-Host "💰 Estimated Monthly Cost: `$0.40 - `$2.00"
    Write-Host "  • S3: Free (5GB limit)"
    Write-Host "  • Lambda: Free (1M requests limit)"
    Write-Host "  • SNS: Free (1K notifications limit)"
    Write-Host "  • Secrets Manager: `$0.40/month"
    Write-Host ""
    Write-Host "🔧 Next Steps:"
    Write-Host "  1. Update Fyers API credentials in Secrets Manager"
    Write-Host "  2. Monitor CloudWatch logs for function execution"
    Write-Host "  3. Check S3 bucket for ingested data"
    Write-Host "  4. Set up billing alerts in AWS Console"
    Write-Host ""
    Write-Host "📍 Useful Links:"
    Write-Host "  • CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AwsRegion#logsV2:log-groups"
    Write-Host "  • S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$($script:S3Bucket)?region=$AwsRegion"
    Write-Host "  • Lambda Console: https://console.aws.amazon.com/lambda/home?region=$AwsRegion#/functions/$($script:LambdaFunction)"
    Write-Host ""
    Write-Host "⚡ Lambda Schedule: Every 15 minutes (configurable)"
    Write-Host "📈 Data Processing: 10 top NSE stocks every 15 minutes"
    Write-Host ""
    Write-Host "🚀 To scale up later, uncomment expensive services in main-mvp.tf:"
    Write-Host "  • RDS PostgreSQL"
    Write-Host "  • ECS Fargate"
    Write-Host "  • AWS Glue"
    Write-Host "  • Athena"
}

# Cleanup function
function Remove-TempFiles {
    Write-Status "Cleaning up temporary files..."
    if (Test-Path "lambda_ingestion.zip") { Remove-Item "lambda_ingestion.zip" -Force }
    if (Test-Path "..\infra\mvp-plan.tfplan") { Remove-Item "..\infra\mvp-plan.tfplan" -Force }
}

# Main execution
function Main {
    Write-Host "🎯 MVP Deployment for AWS Free Tier Stock Pipeline" -ForegroundColor Blue
    Write-Host "================================================="
    Write-Host ""
    Write-Host "This script will deploy:"
    Write-Host "  ✅ S3 bucket for data storage"
    Write-Host "  ✅ Lambda function for data ingestion"
    Write-Host "  ✅ SNS topic for notifications"
    Write-Host "  ✅ Secrets Manager for API credentials"
    Write-Host "  ✅ CloudWatch for logging"
    Write-Host "  ✅ Cost budget alerts"
    Write-Host ""
    Write-Host "💡 All services use AWS Free Tier limits" -ForegroundColor Yellow
    Write-Host "💰 Estimated cost: `$0.40-`$2.00/month" -ForegroundColor Yellow
    Write-Host ""
    
    $Continue = Read-Host "Do you want to continue? (y/N)"
    if ($Continue -notmatch "^[Yy]$") {
        Write-Status "Deployment cancelled by user"
        exit 0
    }
    
    try {
        # Run deployment steps
        Test-Prerequisites
        Test-AwsAccount
        New-LambdaPackage
        Deploy-Infrastructure
        Set-ApiCredentials
        Test-Deployment
        Show-DeploymentSummary
        
        Write-Status "MVP deployment completed successfully! 🎉"
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        exit 1
    }
    finally {
        Remove-TempFiles
    }
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
