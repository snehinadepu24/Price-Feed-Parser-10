# AWS Stock Price Feed Pipeline MVP

A production-ready AWS-based data pipeline for ingesting and processing stock OHLCV (Open, High, Low, Close, Volume) data from the Fyers API with **automatic token management**. The pipeline implements a modern data lake architecture following raw → curated data patterns with comprehensive monitoring and alerting.

## 🔑 Key Feature: Zero-Maintenance Token Management

**NEW**: Your pipeline now includes **automatic token rotation** - set up once, runs forever!

- **No daily login required** - Automatic access token refresh using stored refresh tokens
- **Self-healing** - Invalid tokens are automatically renewed
- **Cost optimized** - Uses free AWS SSM Parameter Store instead of expensive Secrets Manager
- **Production ready** - Robust error handling and monitoring

📖 **[Complete Token Management Guide](TOKEN_MANAGEMENT_GUIDE.md)** - How automatic token rotation works

## Stock Price Feed Parser

A comprehensive AWS-based data pipeline for collecting, processing, and analyzing stock market data from Fyers API. This system provides real-time OHLCV (Open, High, Low, Close, Volume) data ingestion with automated ETL processing and analytics capabilities.

## 🎯 Quick Start for Beginners

**New to AWS?** Start here for a step-by-step guide:

### Option 1: Interactive Setup Wizard (Recommended)
```bash
python scripts/quick_start.py
```
This wizard will guide you through the entire setup process!

### Option 2: Follow the Beginner's Guide
📖 **[Complete Beginner's Guide](BEGINNER_GUIDE.md)** - Detailed step-by-step instructions

### Option 3: Pre-flight Check
```bash
# Check if you have everything needed
python scripts/pre_deployment_check.py

# Windows PowerShell
.\scripts\pre_deployment_check.ps1
```

## 💰 Cost-Optimized MVP Version

**Perfect for learning and prototyping:**
- **Cost**: $0.00-$1.00/month using AWS Free Tier (previously $0.40-$2.00)
- **Optimization**: Uses SSM Parameter Store (free) instead of Secrets Manager ($0.40/month)
- **Features**: Core functionality with 10 stocks, 15-minute intervals
- **Scaling**: Easy upgrade to full production version later

📖 **[MVP Documentation](README-MVP.md)** - Free Tier optimized version

## 🏗️ Architecture Overview

### MVP Architecture (Current - AWS Free Tier)
```
Fyers API → Lambda → S3 Raw → S3 Analytics
             ↓         ↓         ↓
        EventBridge CloudWatch  Athena
             ↓         ↓         ↓
           SNS      Monitoring  Queries
             ↓
    SSM Parameter Store
```

**MVP Components**:
- **Lambda**: Data ingestion (1M free requests/month)
- **EventBridge**: Scheduling (free for all events)
- **S3**: Data storage (5GB free storage)
- **SSM Parameter Store**: Credential management (free for standard parameters)
- **CloudWatch**: Logging & monitoring (5GB free ingestion)
- **SNS**: Notifications (1K free notifications)

### Full Production Architecture (Future Scaling)
```
Fyers API → ECS Fargate → S3 Raw → AWS Glue → S3 Parquet → Athena
                ↓            ↓         ↓          ↓
           EventBridge   CloudWatch  RDS     Data Catalog
                ↓            ↓         ↓          ↓  
              SNS        Monitoring  Metadata   Queries
```

**Production Components** (Commented out in Terraform):
- **ECS Fargate**: Scalable container processing
- **AWS Glue**: Advanced ETL transformations
- **RDS PostgreSQL**: Metadata and reference data
- **Advanced monitoring**: Custom dashboards and metrics

## Tech Stack

### MVP Technology Stack (Current)
- **Language**: Python 3.11
- **AWS Services**: 
  - **Compute**: Lambda (serverless data ingestion)
  - **Storage**: S3 (data lake with lifecycle management)
  - **Orchestration**: EventBridge (scheduling)
  - **Security**: SSM Parameter Store (credential management)
  - **Monitoring**: CloudWatch Logs, SNS (alerts)
- **Infrastructure**: Terraform (Infrastructure as Code)
- **Data Formats**: JSON (raw zone) → Parquet (analytical zone)
- **API**: Fyers API v3 with automatic token refresh

### Full Production Stack (Future)
- **Additional Services**: ECS Fargate, AWS Glue, RDS PostgreSQL, Athena, Secrets Manager
- **Enhanced Features**: Advanced ETL, metadata management, complex analytics

## Key Features

### MVP Features (Currently Active)
- **Automated 15-minute data ingestion** from Fyers API (free tier optimized)
- **Automatic token refresh** - Zero-maintenance credential management
- **Raw JSON to S3** with intelligent partitioning (year/month/day)
- **Cost-optimized S3 lifecycle** management (Standard → IA → Glacier)
- **Comprehensive monitoring** with CloudWatch and SNS alerts
- **Production-ready error handling** and data quality checks
- **Free tier compliant** - $0.00-$1.00/month operational costs
- **Secure credential storage** with SSM Parameter Store (SecureString)

### Production Features (Available via Terraform)
- **Advanced ETL** with AWS Glue for Parquet transformation
- **PostgreSQL metadata** tracking and reference data management
- **Athena query layer** with Data Catalog integration
- **ECS Fargate** containerized processing for high-scale ingestion
- **Advanced monitoring** dashboards and custom metrics

## Project Structure

```
aws-stock-pipeline/
├── ingestion/
│   ├── ingestion.py          # Main ingestion script
│   └── requirements.txt      # Python dependencies
├── etl/
│   └── glue_job.py          # AWS Glue ETL job
├── infra/
│   └── main.tf              # Terraform infrastructure
├── sql/
│   └── schema.sql           # PostgreSQL schema
└── README.md                # This file
```

## 🚀 Deployment Options

### For Beginners (Recommended)
1. **🎯 Quick Start Wizard**: `python scripts/quick_start.py`
2. **📖 Beginner's Guide**: Follow [BEGINNER_GUIDE.md](BEGINNER_GUIDE.md)
3. **💰 MVP Version**: Deploy [cost-optimized version](README-MVP.md) first

### For Experienced Users
1. **🏃‍♂️ Direct MVP Deployment**:
   ```bash
   cd deployment
   ./deploy-mvp.sh  # Linux/Mac
   # OR
   .\deploy-mvp.ps1 -NotificationEmail "your-email@example.com"  # Windows
   ```

2. **🏭 Full Production Deployment**:
   ```bash
   cd deployment
   ./deploy.sh  # Full infrastructure with RDS, ECS, Glue
   ```

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- Docker installed (for building container images)
- Fyers API account with valid credentials
- Valid email address for SNS notifications

## Deployment Steps

### 1. Infrastructure Deployment

Clone the repository and deploy infrastructure:

```bash
git clone <repo-url>
cd aws-stock-pipeline

# Initialize Terraform
cd infra
terraform init

# Review and apply infrastructure
terraform plan -var="notification_email=your-email@example.com"
terraform apply -var="notification_email=your-email@example.com"
```

### 2. Configure Fyers API Credentials

After infrastructure deployment, update SSM Parameter Store with your Fyers API credentials:

```bash
# Get the parameter names from Terraform output
terraform output fyers_parameter_prefix

# Update SSM parameters with your actual credentials (ONE TIME SETUP)
aws ssm put-parameter \
  --name "/stock-pipeline-mvp/fyers/client_id" \
  --value "YOUR_FYERS_CLIENT_ID" \
  --type "SecureString" \
  --overwrite

aws ssm put-parameter \
  --name "/stock-pipeline-mvp/fyers/app_secret" \
  --value "YOUR_FYERS_APP_SECRET" \
  --type "SecureString" \
  --overwrite

aws ssm put-parameter \
  --name "/stock-pipeline-mvp/fyers/refresh_token" \
  --value "YOUR_FYERS_REFRESH_TOKEN" \
  --type "SecureString" \
  --overwrite

# Optional: PIN (only if required by your Fyers account)
aws ssm put-parameter \
  --name "/stock-pipeline-mvp/fyers/pin" \
  --value "YOUR_FYERS_PIN" \
  --type "SecureString" \
  --overwrite

# Access tokens are automatically generated and managed by Lambda
# No manual access token management required!
```

**Important**: You need these credentials from your Fyers API app:
- **client_id**: Your app ID (e.g., `ABC123XY-100`)
- **app_secret**: Your app secret (used for authentication hash)
- **refresh_token**: Long-lived token (15-day validity, auto-refresh access tokens)
- **pin**: Your trading PIN (optional, only required for some accounts)

### 3. Test MVP Pipeline

Your MVP pipeline is now ready to run automatically:

```bash
# Test Lambda function manually
aws lambda invoke \
  --function-name stock-pipeline-mvp-ingestion \
  --payload '{}' \
  response.json

# Check CloudWatch logs for token refresh activity
aws logs tail /aws/lambda/stock-pipeline-mvp-ingestion --follow

# Verify data in S3
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/mvp-raw/ --recursive
```

## Production Deployment (Future Scaling)

When you're ready to scale beyond the MVP, uncomment the production services in `infra/main-mvp.tf`:

### 3. Build and Deploy Container (Production Only)

```bash
# For ECS Fargate deployment (commented out in MVP)
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push container
docker build -t stock-pipeline-ingestion ./ingestion/
docker tag stock-pipeline-ingestion:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### 4. Deploy Glue ETL Script (Production Only)

```bash
# Upload Glue job script to S3 (when using AWS Glue)
SCRIPT_BUCKET=$(terraform output -raw glue_scripts_bucket)
aws s3 cp etl/glue_job.py s3://$SCRIPT_BUCKET/etl/glue_job.py
```

### 5. Initialize Database Schema (Production Only)

```bash
# Connect to RDS PostgreSQL (when using RDS)
RDS_CREDS=$(aws secretsmanager get-secret-value --secret-id $(terraform output -raw rds_secret_name) --query SecretString --output text)
DB_HOST=$(echo $RDS_CREDS | jq -r '.host')
DB_USER=$(echo $RDS_CREDS | jq -r '.username')
DB_PASS=$(echo $RDS_CREDS | jq -r '.password')
DB_NAME=$(echo $RDS_CREDS | jq -r '.dbname')

# Execute schema
PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f sql/rds_schema.sql
```

## Usage

### MVP Data Access

Your MVP pipeline stores data in S3 with the following structure:

```bash
# Check your data in S3
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/mvp-raw/ --recursive --human-readable

# Download sample data for analysis
aws s3 cp s3://$(terraform output -raw s3_bucket_name)/mvp-raw/year=2025/month=08/day=29/ . --recursive
```

### Manual Ingestion Test (MVP)

Test the Lambda function manually:

```bash
# Invoke Lambda function
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{}' \
  response.json

# Check response
cat response.json

# Monitor logs in real-time
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
```

### Querying Data with Athena (Production)

When you scale to production with Glue ETL, you can query processed data:

```sql
-- Create external table (run once)
CREATE EXTERNAL TABLE ohlcv_data (
  symbol string,
  resolution string,
  timestamp timestamp,
  open double,
  high double,
  low double,
  close double,
  volume bigint,
  fetch_timestamp string,
  hour int,
  ingested_at timestamp
)
PARTITIONED BY (
  year int,
  month int,
  day int,
  symbol_clean string
)
STORED AS PARQUET
LOCATION 's3://your-bucket-name/parquet/resolution=5/'
TBLPROPERTIES ('has_encrypted_data'='false');

-- Load partitions
MSCK REPAIR TABLE ohlcv_data;

-- Query examples
-- Get latest data for Reliance
SELECT *
FROM ohlcv_data
WHERE symbol_clean = 'RELIANCE'
  AND year = 2025
ORDER BY timestamp DESC
LIMIT 100;

-- Top 10 stocks by volume today
SELECT 
  symbol_clean,
  SUM(volume) as total_volume,
  AVG(close) as avg_price,
  COUNT(*) as data_points
FROM ohlcv_data
WHERE year = 2025 
  AND month = 1
  AND day = EXTRACT(day FROM CURRENT_DATE)
GROUP BY symbol_clean
ORDER BY total_volume DESC
LIMIT 10;

-- Join with market cap data (requires RDS federation or exported data)
SELECT 
  o.symbol_clean,
  o.close,
  o.volume,
  o.timestamp
FROM ohlcv_data o
WHERE o.year = 2025
  AND o.symbol_clean IN (
    SELECT symbol FROM top_500_by_marketcap  -- This would be a pre-computed list
  )
ORDER BY o.timestamp DESC;
```

### Monitoring and Alerting

Monitor the pipeline through:

1. **CloudWatch Dashboards**: View metrics for ECS tasks, Glue jobs, and S3 operations
2. **SNS Notifications**: Receive alerts for ingestion/ETL failures
3. **RDS Metadata**: Query processing statistics and data quality metrics

```sql
-- Check recent ingestion statistics
SELECT * FROM stock_data.v_ingestion_summary 
ORDER BY processing_date DESC 
LIMIT 7;

-- Monitor data quality
SELECT 
  table_name,
  metric_name,
  metric_value,
  is_within_threshold,
  measurement_date
FROM stock_data.data_quality_metrics
WHERE measurement_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY measurement_date DESC;
```

## Configuration

### Environment Variables

Key environment variables used by the MVP pipeline:

**MVP Lambda Environment Variables**:
- `S3_BUCKET_NAME`: S3 bucket for data storage
- `FYERS_ACCESS_TOKEN_PARAM`: SSM parameter name for access token (auto-managed)
- `FYERS_REFRESH_TOKEN_PARAM`: SSM parameter name for refresh token
- `FYERS_CLIENT_ID_PARAM`: SSM parameter name for client ID
- `FYERS_APP_SECRET_PARAM`: SSM parameter name for app secret
- `SNS_TOPIC_ARN`: SNS topic for notifications
- `ENVIRONMENT`: Environment name (dev/staging/prod)

**Production Environment Variables** (when scaling up):
- `RDS_SECRET_NAME`: Database connection credentials  
- `GLUE_DATABASE_NAME`: AWS Glue catalog database name

### Scheduling

- **Ingestion**: Every 5 minutes via EventBridge
- **ETL Processing**: Daily at 2:00 AM UTC
- **Token Refresh**: Daily at 6:30 AM IST (1:00 AM UTC)

### Cost Optimization

The pipeline includes several cost optimization features:

- **S3 Lifecycle Management**: Automatic transition to cheaper storage classes
- **Parquet Compression**: Snappy compression for efficient storage
- **Spot Instances**: Can be configured for Glue jobs (not implemented in MVP)
- **Data Retention**: Configurable retention policies for raw data

## Troubleshooting

### Common Issues

1. **Token Expiry**: Check Fyers API token validity in SSM Parameter Store
2. **Network Issues**: Verify Lambda configuration and IAM permissions
3. **Permission Errors**: Review IAM roles and SSM parameter access
4. **Data Quality**: Monitor processing logs in CloudWatch

### Debugging Commands

```bash
# MVP Debugging Commands
# Check Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# Check SSM parameters
aws ssm get-parameters \
  --names "$(terraform output -raw fyers_client_id_param)" \
          "$(terraform output -raw fyers_refresh_token_param)" \
  --with-decryption

# Verify S3 data structure
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/ --recursive --human-readable

# Check EventBridge rule status
aws events list-rules --name-prefix "stock-pipeline-mvp"

# Production Debugging Commands (when scaling up)
# Check ECS task logs
aws logs tail /ecs/stock-pipeline-ingestion --follow

# Check Glue job status  
aws glue get-job-runs --job-name stock-pipeline-etl

# Test RDS connectivity
PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();"
```

## Security Considerations

### MVP Security Features
- **Credential Management**: All credentials stored in SSM Parameter Store (SecureString with AWS KMS encryption)
- **Access Control**: IAM roles follow principle of least privilege
- **Data Encryption**: S3 bucket encryption enabled (AES-256)
- **Network Security**: Lambda runs in AWS managed VPC
- **Cost Controls**: AWS Budget alerts to prevent bill shock

### Production Security Features (Future)
- **Network Isolation**: VPC with private subnets for RDS and ECS
- **Advanced Secrets**: AWS Secrets Manager for complex credential rotation
- **Enhanced Monitoring**: GuardDuty and CloudTrail integration

## Future Enhancements

- Real-time streaming with Kinesis Data Streams
- Advanced analytics with EMR or SageMaker
- Web dashboard using QuickSight or custom frontend
- Additional data sources and APIs
- Machine learning models for price prediction
- Data validation and anomaly detection

## Support

For issues and questions:

1. Check CloudWatch logs for error details
2. Verify AWS service limits and quotas
3. Review Terraform state for infrastructure issues
4. Monitor SNS notifications for system alerts

## License

This project is provided as-is for educational and development purposes. Please ensure compliance with Fyers API terms of service and data usage policies.