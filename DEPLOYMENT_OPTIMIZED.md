# 🚀 Optimized AWS Stock Pipeline Deployment Guide

## Overview of Optimizations Implemented

### ✅ **Terraform State Management**
- Remote S3 backend with DynamoDB locking
- State encryption and versioning
- Team collaboration support

### ✅ **Resource Sizing & Performance**
- ECS tasks: 1024 CPU / 2048 MB memory (optimized for 30+ stocks)
- Glue jobs: G.1X workers with FLEX execution (Spot instances)
- RDS: GP3 storage for better cost/performance ratio

### ✅ **Error Recovery & Resilience**
- Circuit breaker pattern for API calls
- Exponential backoff with jitter
- Batch processing with rate limiting
- Comprehensive retry mechanisms

### ✅ **Cost Optimization**
- S3 lifecycle policies (Standard → IA → Glacier → Deep Archive)
- CloudWatch log retention policies (3-14 days)
- RDS backup optimization (3 days)
- Cost budgets and alerts ($50/month limit)
- Spot instances for Glue jobs

## Pre-Deployment Setup

### 1. Setup Terraform Backend (One-time)

```bash
# Make the script executable and run it
chmod +x deployment/setup-terraform-backend.sh
./deployment/setup-terraform-backend.sh
```

This will create:
- S3 bucket for Terraform state
- DynamoDB table for state locking
- Proper encryption and access controls

### 2. Update Terraform Backend Configuration

After running the setup script, update `infra/main.tf` with the bucket name provided:

```hcl
terraform {
  backend "s3" {
    bucket         = "stock-pipeline-terraform-state-your-suffix"
    key            = "stock-pipeline/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-your-suffix"
  }
}
```

## Deployment Steps

### 1. Initialize and Deploy Infrastructure

```bash
cd infra

# Initialize with remote backend
terraform init

# Plan with optimized configuration
terraform plan \
  -var="notification_email=your-email@example.com" \
  -var="aws_region=ap-south-1" \
  -var="environment=dev"

# Apply infrastructure
terraform apply \
  -var="notification_email=your-email@example.com" \
  -var="aws_region=ap-south-1" \
  -var="environment=dev" \
  -auto-approve
```

### 2. Configure API Credentials

```bash
# Get secret name and update credentials
SECRET_NAME=$(terraform output -raw fyers_secret_name)

aws secretsmanager update-secret \
  --secret-id $SECRET_NAME \
  --secret-string '{
    "access_token": "YOUR_FYERS_ACCESS_TOKEN",
    "refresh_token": "YOUR_FYERS_REFRESH_TOKEN",
    "client_id": "YOUR_FYERS_CLIENT_ID"
  }'
```

### 3. Build and Deploy Optimized Container

```bash
# Get ECR details
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build optimized container
cd ../
docker build -t stock-pipeline-ingestion ./ingestion/ \
  --build-arg PYTHON_VERSION=3.11-slim \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Tag and push
docker tag stock-pipeline-ingestion:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### 4. Deploy Glue ETL Script

```bash
# Upload optimized Glue script
SCRIPT_BUCKET=$(terraform output -raw glue_scripts_bucket)
aws s3 cp etl/glue_job.py s3://$SCRIPT_BUCKET/etl/glue_job.py
```

## Monitoring & Cost Management

### 1. Access CloudWatch Dashboard

```bash
# Get dashboard URL
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"
```

### 2. Monitor Costs

```bash
# Check current month's costs
aws ce get-cost-and-usage \
  --time-period Start=2025-08-01,End=2025-08-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Check budget status
aws budgets describe-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name $(terraform output -raw cost_budget_name)
```

### 3. Performance Testing

```bash
# Run manual ingestion test
./deployment/test-pipeline.sh

# Monitor ECS task performance
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks \
    --cluster $(terraform output -raw ecs_cluster_name) \
    --query 'taskArns[0]' --output text)
```

## Cost Optimization Features

### Implemented Cost Controls

1. **Storage Lifecycle Management**
   - Raw data: Standard (7 days) → IA (30 days) → Glacier (180 days) → Deep Archive
   - Processed data: Standard (30 days) → IA (90 days) → Glacier (365 days) → Deep Archive

2. **Compute Optimization**
   - Glue jobs use Spot instances (FLEX execution class)
   - ECS tasks right-sized for workload
   - RDS uses burstable instances (t3.micro)

3. **Monitoring Costs**
   - Monthly budget: $50 with 80% and 100% alerts
   - Log retention: 3-14 days maximum
   - Automated cleanup of incomplete uploads

### Expected Monthly Costs (Estimate)

| Service | Estimated Cost |
|---------|----------------|
| ECS Fargate | $10-15 |
| RDS (t3.micro) | $12-18 |
| S3 Storage | $5-10 |
| Glue ETL | $8-12 |
| CloudWatch | $3-5 |
| **Total** | **$38-60** |

## Troubleshooting Guide

### High Error Rates
```bash
# Check circuit breaker status in logs
aws logs filter-log-events \
  --log-group-name "/ecs/stock-pipeline-ingestion" \
  --filter-pattern "circuit_breaker_state"

# Check API rate limiting
aws logs filter-log-events \
  --log-group-name "/ecs/stock-pipeline-ingestion" \
  --filter-pattern "rate_limit"
```

### Cost Overruns
```bash
# Check largest cost contributors
aws ce get-cost-and-usage \
  --time-period Start=2025-08-01,End=2025-08-31 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Performance Issues
```bash
# Check Glue job metrics
aws glue get-job-runs --job-name stock-pipeline-etl --max-items 5

# Monitor ECS CPU/Memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=stock-pipeline-ingestion \
  --start-time 2025-08-28T00:00:00Z \
  --end-time 2025-08-28T23:59:59Z \
  --period 3600 \
  --statistics Average
```

## Maintenance

### Weekly Tasks
- Review cost dashboard
- Check error rates and success metrics
- Verify data quality metrics

### Monthly Tasks
- Analyze budget vs actual costs
- Review and optimize resource sizing
- Update security credentials if needed

### Quarterly Tasks
- Review and update lifecycle policies
- Evaluate need for additional cost optimizations
- Performance benchmarking and tuning

This optimized deployment addresses all the critical issues identified in the review and provides a production-ready, cost-effective AWS data pipeline.
