#!/usr/bin/env pwsh
# Deploy Token Generator to existing AWS infrastructure
# This script integrates the token generator with your existing pipeline

param(
    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail,
    
    [string]$Region = "ap-south-1",
    [string]$ProjectName = "stock-pipeline-mvp"
)

Write-Host "🚀 Deploying AWS Token Generator to existing infrastructure..." -ForegroundColor Green
Write-Host "📧 Notification Email: $NotificationEmail"
Write-Host "🌍 Region: $Region"
Write-Host "📦 Project: $ProjectName"

# Check prerequisites
Write-Host "`n✅ Checking prerequisites..."

# Check if AWS CLI is available
if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    exit 1
}

# Check if Terraform is available
if (-not (Get-Command "terraform" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Terraform not found. Please install Terraform first." -ForegroundColor Red
    exit 1
}

# Check AWS credentials
Write-Host "🔐 Checking AWS credentials..."
try {
    $callerIdentity = aws sts get-caller-identity 2>$null | ConvertFrom-Json
    Write-Host "✅ AWS credentials valid. Account: $($callerIdentity.Account)" -ForegroundColor Green
}
catch {
    Write-Host "❌ AWS credentials not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

# Navigate to infrastructure directory
Set-Location "$PSScriptRoot\..\infra"

Write-Host "`n🏗️ Deploying infrastructure with Token Generator..."

# Initialize Terraform if needed
if (-not (Test-Path ".terraform")) {
    Write-Host "📦 Initializing Terraform..."
    terraform init
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Terraform initialization failed!" -ForegroundColor Red
        exit 1
    }
}

# Plan deployment
Write-Host "📋 Planning deployment..."
terraform plan -var="notification_email=$NotificationEmail" -var="aws_region=$Region" -var="project_name=$ProjectName"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Terraform plan failed!" -ForegroundColor Red
    exit 1
}

# Ask for confirmation
$confirmation = Read-Host "`n🤔 Do you want to proceed with deployment? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "❌ Deployment cancelled by user." -ForegroundColor Yellow
    exit 0
}

# Apply deployment
Write-Host "🚀 Applying deployment..."
terraform apply -auto-approve -var="notification_email=$NotificationEmail" -var="aws_region=$Region" -var="project_name=$ProjectName"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Terraform apply failed!" -ForegroundColor Red
    exit 1
}

# Get outputs
Write-Host "`n📊 Getting deployment outputs..."
$outputs = terraform output -json | ConvertFrom-Json

$tokenGeneratorUrl = $outputs.token_generator_url.value
$s3BucketName = $outputs.s3_bucket_name.value
$lambdaFunctionName = $outputs.lambda_function_name.value

Write-Host "`n🎉 Deployment completed successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n🔑 TOKEN GENERATOR ACCESS:" -ForegroundColor Yellow
Write-Host "   Web UI URL: $tokenGeneratorUrl" -ForegroundColor Green
Write-Host "   📱 Bookmark this URL for daily token generation!" -ForegroundColor Cyan

Write-Host "`n📦 PIPELINE RESOURCES:" -ForegroundColor Yellow
Write-Host "   S3 Bucket: $s3BucketName" -ForegroundColor Green
Write-Host "   Lambda Function: $lambdaFunctionName" -ForegroundColor Green

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "   1. 🌐 Open: $tokenGeneratorUrl" -ForegroundColor Cyan
Write-Host "   2. 🔑 Enter your Fyers Client ID and App Secret" -ForegroundColor Cyan
Write-Host "   3. 🔐 Generate tokens using the web interface" -ForegroundColor Cyan
Write-Host "   4. ✅ Your pipeline will automatically use the new tokens!" -ForegroundColor Cyan

Write-Host "`n💡 DAILY WORKFLOW:" -ForegroundColor Yellow
Write-Host "   • Open the web UI every morning" -ForegroundColor Cyan
Write-Host "   • Generate fresh tokens in 3 clicks" -ForegroundColor Cyan
Write-Host "   • No more command-line tools needed!" -ForegroundColor Cyan

Write-Host "`n🔍 MONITORING:" -ForegroundColor Yellow
Write-Host "   CloudWatch: https://$Region.console.aws.amazon.com/cloudwatch/home?region=$Region#logsV2:log-groups/log-group/%252Faws%252Flambda%252F$ProjectName-ingestion" -ForegroundColor Green
Write-Host "   S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$s3BucketName?region=$Region" -ForegroundColor Green

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🎯 Your AWS-hosted token generator is ready!" -ForegroundColor Green

# Save the URL to a file for easy access
$tokenGeneratorUrl | Out-File -FilePath "$PSScriptRoot\..\token-generator-url.txt" -Encoding UTF8
Write-Host "`n💾 Token generator URL saved to: token-generator-url.txt" -ForegroundColor Cyan
