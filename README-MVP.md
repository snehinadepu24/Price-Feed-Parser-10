# 🎯 Stock Price Feed Parser - MVP Edition

**AWS Free Tier Optimized Stock Data Pipeline**

This is a **Minimum Viable Product (MVP)** version of the stock price feed parser, specifically designed to work within AWS Free Tier limits while demonstrating the core functionality. Perfect for prototyping, learning, and cost-conscious development.

## 💰 Cost Breakdown

### Free Tier Services (Active in MVP)
- **S3**: 5GB storage, 20,000 GET requests, 2,000 PUT requests/month ✅ **FREE**
- **Lambda**: 1M requests, 400,000 GB-seconds/month ✅ **FREE**
- **SNS**: 1,000 notifications/month ✅ **FREE**
- **CloudWatch Logs**: 5GB ingestion, 5GB storage/month ✅ **FREE**
- **EventBridge**: All scheduled events ✅ **FREE**
- **SSM Parameter Store**: Free for standard parameters ✅ **FREE**

### **Total Estimated Cost: $0.00/month (Completely Free!)**

## 🚀 What's Included in MVP

### ✅ Active Services
1. **Data Ingestion**: Lambda function fetching stock data every 15 minutes
2. **Data Storage**: S3 bucket with intelligent lifecycle management
3. **Monitoring**: SNS notifications for success/failure alerts
4. **Security**: AWS SSM Parameter Store for API credentials (free)
5. **Cost Control**: Budget alerts at 50% and 80% of $5 monthly budget
6. **Local Analytics**: Python scripts for data visualization

### 📦 MVP Data Pipeline
```
Fyers API → Lambda Function → S3 Storage → Local Analysis → Charts & Reports
    ↓
   SNS Notifications (Email Alerts)
```

### 🔒 Commented Out (Expensive Services)
These services are preserved in code but commented out to avoid costs:
- **RDS PostgreSQL** (~$15-20/month)
- **ECS Fargate** (~$20-50/month)
- **AWS Glue** (~$5-10/month)
- **Athena** (pay-per-query after 10TB)

## 📋 Prerequisites

1. **AWS Account** with Free Tier availability
2. **AWS CLI** installed and configured
3. **Terraform** >= 1.0
4. **Fyers API Credentials** (access_token, client_id, refresh_token)
5. **Python 3.8+** for local analysis
6. **Email address** for notifications

## 🛠️ Quick Start

### 1. Clone and Setup
```bash
git clone <repository>
cd "Price Feed Parser"
```

### 2. Deploy MVP Infrastructure

**For Windows (PowerShell):**
```powershell
cd deployment
.\deploy-mvp.ps1 -NotificationEmail "your-email@example.com"
```

**For Linux/Mac (Bash):**
```bash
cd deployment
export NOTIFICATION_EMAIL="your-email@example.com"
./deploy-mvp.sh
```

### 3. Configure API Credentials
After deployment, update your Fyers API credentials in AWS SSM Parameter Store (free):

```bash
# Set Fyers API credentials in SSM Parameter Store
aws ssm put-parameter \
    --name "/stock-pipeline-mvp/fyers/access_token" \
    --value "YOUR_ACCESS_TOKEN" \
    --type "SecureString" \
    --overwrite

aws ssm put-parameter \
    --name "/stock-pipeline-mvp/fyers/refresh_token" \
    --value "YOUR_REFRESH_TOKEN" \
    --type "SecureString" \
    --overwrite

aws ssm put-parameter \
    --name "/stock-pipeline-mvp/fyers/client_id" \
    --value "YOUR_CLIENT_ID" \
    --type "SecureString" \
    --overwrite
```

### 4. Monitor and Analyze
- **CloudWatch Logs**: Monitor Lambda execution
- **S3 Console**: View stored data files
- **Local Analysis**: Run the MVP analyzer script

## 📊 Data Analysis (Local)

### Setup Analysis Environment
```bash
cd analysis
pip install pandas matplotlib seaborn boto3
```

### Run Analysis
```bash
export S3_BUCKET_NAME="your-mvp-bucket-name"
python mvp_analyzer.py
```

### Generated Outputs
- **Charts**: Price trends, volume analysis, correlations
- **Reports**: Daily statistics and market summary
- **Data**: Processed CSV files for further analysis

## 📈 MVP Specifications

### Data Collection
- **Frequency**: Every 15 minutes (configurable)
- **Symbols**: Top 10 NSE stocks (configurable)
- **Resolution**: 15-minute OHLCV data
- **Storage**: JSON format in S3

### Monitoring
- **Email Alerts**: Success/failure notifications
- **CloudWatch Logs**: Detailed execution logs
- **Cost Alerts**: Budget notifications at 50% and 80%

### Limitations (MVP)
- Limited to 10 stocks (vs 30+ in full version)
- 15-minute intervals (vs 5-minute in full version)
- Local analysis only (no cloud analytics)
- JSON storage (no database optimization)
- Basic error handling (no advanced retry mechanisms)

## 🔧 Configuration

### Environment Variables
```bash
# Required
NOTIFICATION_EMAIL="your-email@example.com"

# Optional
AWS_REGION="ap-south-1"
PROJECT_NAME="stock-pipeline-mvp"
```

### Terraform Variables
```hcl
variable "notification_email" {
  description = "Email for alerts"
  type        = string
}

variable "aws_region" {
  default = "ap-south-1"
}

variable "project_name" {
  default = "stock-pipeline-mvp"
}
```

## 📱 Monitoring & Alerts

### CloudWatch Dashboard
```
https://console.aws.amazon.com/cloudwatch/home?region=ap-south-1#dashboards
```

### S3 Data Browser
```
https://s3.console.aws.amazon.com/s3/buckets/YOUR_BUCKET_NAME
```

### Lambda Function Logs
```
https://console.aws.amazon.com/lambda/home?region=ap-south-1#/functions/stock-pipeline-mvp-ingestion
```

## 🚀 Scaling to Production

When ready to scale beyond MVP, uncomment the following services in `main-mvp.tf`:

### 1. Enable Database Storage
```hcl
# Uncomment RDS PostgreSQL section
resource "aws_db_instance" "postgres" {
  # ... configuration
}
```

### 2. Enable Container Processing
```hcl
# Uncomment ECS Fargate section
resource "aws_ecs_cluster" "main" {
  # ... configuration
}
```

### 3. Enable ETL Processing
```hcl
# Uncomment AWS Glue section
resource "aws_glue_job" "etl" {
  # ... configuration
}
```

### 4. Enable Analytics
```hcl
# Uncomment Athena section
resource "aws_athena_workgroup" "ohlcv" {
  # ... configuration
}
```

## 🔍 Troubleshooting

### Common Issues

**1. Lambda Timeout**
```bash
# Check CloudWatch logs
aws logs tail /aws/lambda/stock-pipeline-mvp-ingestion --follow
```

**2. API Rate Limits**
- MVP uses 2-second delays between API calls
- Reduce symbol count if needed
- Check Fyers API quotas

**3. S3 Access Issues**
```bash
# Verify bucket permissions
aws s3 ls s3://your-bucket-name/
```

**4. Cost Overruns**
- Monitor AWS Billing Dashboard
- Check budget alerts
- Verify Free Tier usage

### Debug Commands
```bash
# Test Lambda function
aws lambda invoke --function-name stock-pipeline-mvp-ingestion test-output.json

# Check S3 data
aws s3 ls s3://your-bucket-name/mvp-raw/ --recursive

# View recent logs
aws logs filter-log-events --log-group-name /aws/lambda/stock-pipeline-mvp-ingestion --start-time $(date -d '1 hour ago' +%s)000
```

## 📋 File Structure

```
Price Feed Parser/
├── infra/
│   ├── main.tf              # Full production infrastructure
│   ├── main-mvp.tf          # MVP infrastructure (Free Tier)
│   └── monitoring.tf        # CloudWatch dashboards
├── ingestion/
│   ├── ingestion.py         # Full ECS-based ingestion
│   ├── lambda_ingestion.py  # MVP Lambda ingestion
│   └── requirements.txt     # Python dependencies
├── deployment/
│   ├── deploy-mvp.sh        # Bash deployment script
│   └── deploy-mvp.ps1       # PowerShell deployment script
├── analysis/
│   └── mvp_analyzer.py      # Local data analysis
└── README-MVP.md            # This file
```

## 🎯 Next Steps

1. **Deploy MVP** and verify functionality
2. **Monitor costs** in AWS Billing Dashboard
3. **Analyze data** using local Python scripts
4. **Scale gradually** by enabling additional services
5. **Optimize costs** based on usage patterns

## 🤝 Support

For issues and questions:
1. Check CloudWatch logs for execution details
2. Verify AWS Free Tier limits
3. Review Fyers API documentation
4. Monitor cost and usage in AWS Console

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**⚠️ Important**: This MVP is designed for learning and prototyping. For production use, enable the full infrastructure with proper error handling, monitoring, and security measures.
