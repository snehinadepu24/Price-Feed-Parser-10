# AWS Stock Price Feed Pipeline

A cost-conscious AWS data pipeline for ingesting and processing stock OHLCV (Open, High, Low, Close, Volume) data from the Fyers API with **automatic token management**. The refreshed architecture keeps the interactive token UI, trims production-only services, and now uses a Python ETL to publish lean Parquet analytics that Athena can query.

## 🧭 What’s Included in the Lean MVP
- **Ingestion Lambda** scheduled by EventBridge, persisting raw JSON to S3
- **Python ETL Lambda/CLI** producing curated Parquet files in S3
- **Token generator web UI** backed by API Gateway + Lambda, storing secrets in SSM
- **SNS alerts** and **CloudWatch logs** for monitoring
- **Terraform configuration** limited to free-tier friendly components

---

## 🚀 Getting Started

### 1. Deploy the Lean Infrastructure
```bash
cd infra
terraform init
terraform plan -var="notification_email=you@example.com"
terraform apply -var="notification_email=you@example.com"
```
Keep the Terraform outputs handy—they provide the S3 bucket, Lambda names, and token UI URL.

### 2. Configure Fyers Credentials Once
```bash
terraform output -raw fyers_parameter_prefix

aws ssm put-parameter --name "/stock-pipeline/fyers/client_id" \
  --value "YOUR_CLIENT_ID" --type "SecureString" --overwrite
aws ssm put-parameter --name "/stock-pipeline/fyers/app_secret" \
  --value "YOUR_APP_SECRET" --type "SecureString" --overwrite
aws ssm put-parameter --name "/stock-pipeline/fyers/refresh_token" \
  --value "YOUR_REFRESH_TOKEN" --type "SecureString" --overwrite
# Optional PIN
aws ssm put-parameter --name "/stock-pipeline/fyers/pin" \
  --value "YOUR_PIN" --type "SecureString" --overwrite
```
Access tokens are generated automatically by the ingestion Lambda—no daily login required.

### 3. Use the Interactive Token UI (Optional Step)
```
https://{api-id}.execute-api.{region}.amazonaws.com/prod
```
- Paste your refresh token and client details
- Generate a fresh access token
- Lambda stores it in SSM under the configured parameters

---

## 🧰 Repository Structure (Lean Version)
```
ingestion/                # Ingestion Lambda source
  lambda_ingestion.py
  requirements.txt
etl/
  requirements.txt       # Shared Python deps for ETL
  python_etl/
    __init__.py
    job.py               # Lambda/CLI entry point
    transforms.py        # Row normalization helpers
  lambda_handler.py      # Thin wrapper calling job.run()
  cli.py                 # Enables python -m etl.cli --date ...
infra/
  main.tf                # Free-tier Terraform stack
aws-token-generator/
  lambda_function.py     # Token generator backend
README.md                # This file
```

---

## 🔁 Data Flow
```
Fyers API → Ingestion Lambda → S3 raw/ohlcv/YYYY-MM-DD/data.json
                                ↓
                        EventBridge schedule
                                ↓
Python ETL (Lambda or CLI) → S3 analytics/ohlcv/year=YYYY/month=MM/day=DD/part-*.parquet
                                ↓
                             Athena (manual/optional queries)
```

- **Raw zone** keeps the complete JSON response for audit/backfill
- **Analytics zone** stores denormalized Parquet with the essential columns for Athena
- **Partitions** follow year/month/day to keep Athena scans small

---

## 🐍 Python ETL Details

### Key Behaviors
- Streams raw S3 objects, normalizes to a minimal schema, and writes Parquet with Snappy compression
- Works as an AWS Lambda (single date auto-picked from invocation event) or a CLI tool for backfills
- Implements simple rate limiting, retry, and idempotent writes (skip if partition already exists unless `--force`)
- Requires `pandas` + `pyarrow`, packaged via `etl/requirements.txt`

### Lambda Handler
```python
from etl.python_etl.job import run_etl

def handler(event, context):
    # event can include {"target_date": "2025-01-10"}
    run_etl(event=event, context=context)
```

### CLI Example
```bash
python -m etl.cli --date 2025-01-10 --bucket stock-pipeline-dev-ohlcv-abc123 --region ap-south-1
```
Use this from a container, ECS task, or Step Functions when you need bulk backfills.

---

## 🗂️ Athena Table Definition (Updated)
```sql
CREATE EXTERNAL TABLE IF NOT EXISTS ohlcv_close_only (
  symbol string,
  candle_start timestamp,
  close double,
  volume bigint,
  ingested_at timestamp
)
PARTITIONED BY (
  year int,
  month int,
  day int
)
STORED AS PARQUET
LOCATION 's3://<your-s3-bucket>/analytics/ohlcv/'
TBLPROPERTIES (
  'classification'='parquet',
  'projection.enabled'='false'
);

MSCK REPAIR TABLE ohlcv_close_only;
```

### Sample Query
```sql
SELECT symbol,
       DATE(candle_start) AS trading_day,
       MAX(close) AS day_high,
       MIN(close) AS day_low,
       SUM(volume) AS total_volume
FROM ohlcv_close_only
WHERE year = 2025 AND month = 1
GROUP BY symbol, DATE(candle_start)
ORDER BY trading_day DESC, symbol;
```

---

## 🔍 Observability & Operations
1. **CloudWatch Logs**: `terraform output cloudwatch_logs_url`
2. **SNS Alerts**: Delivery status and failures reach your email
3. **Cost Guardrail**: AWS Budgets alert at 50% and 80% of the $5 cap
4. **S3 Validation**: `aws s3 ls s3://$(terraform output -raw s3_bucket_name)/analytics/ --recursive`

### Manual Lambda Test
```bash
aws lambda invoke --function-name $(terraform output -raw lambda_function_name) --payload '{}' response.json
cat response.json
```

### Trigger Python ETL via Lambda (same date as ingestion run)
```bash
aws lambda invoke \
  --function-name stock-pipeline-etl \
  --payload '{"target_date": "2025-01-10"}' \
  response-etl.json
```

---

## 🛠️ Local Development Tips
- Create a virtual environment per component (`ingestion`, `etl`)
- Use the CLI to test transformations locally with sample S3 files downloaded via `aws s3 cp`
- When extending schema, update `transforms.py` + the Athena DDL together
- Keep rate limits in mind while increasing symbol coverage; throttle via ETL config if necessary

---

## 📈 Roadmap Ideas (Optional Enhancements)
- Step Functions orchestration to chain ingestion and ETL automatically
- On-demand full backfill script leveraging AWS Batch/ECS
- Data quality checks emitting CloudWatch metrics
- Partition projection + Glue crawler for hands-free Athena updates

---

## 🙌 Credits
- Maintains the original interactive token workflow requested by the team
- Simplified Terraform authored to stay inside the AWS free tier
- Python ETL designed for Lambda first, with ECS/container expansion ready when needed

Happy building! 🏗️📊
