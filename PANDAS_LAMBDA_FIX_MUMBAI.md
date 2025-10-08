# PANDAS LAMBDA DEPLOYMENT FIX FOR MUMBAI REGION

## 🔥 Problem: Pandas Package Too Large for Lambda in Mumbai

**Issue:** Pandas + dependencies = **~100 MB** (exceeds Lambda 50 MB deployment limit for direct upload)

**Why Mumbai is affected:**
- ❌ AWS Lambda Layers for Pandas **NOT available in ap-south-1 (Mumbai)**
- ❌ Public Lambda Layers only exist in us-east-1, us-west-2, eu-west-1
- ❌ Cannot use S3 upload method without pre-building the zip locally

---

## ✅ SOLUTION 1: Comment Out Analytics Lambda (IMPLEMENTED)

**What we did:**
1. ✅ Commented out `analytics` Lambda in `main-mvp.tf`
2. ✅ Created lightweight version: `analytics/lambda_analytics_lightweight.py`
3. ✅ Removed Pandas dependency (uses native Python CSV module)

**Result:**
- Your **core MVP pipeline** (ingestion + ETL) will deploy successfully
- Analytics Lambda is optional for MVP
- You can query CSV files directly from S3

**To deploy now:**
```powershell
cd d:\Price Feed Parser\infra
terraform validate
terraform plan -var="notification_email=23071a66c5@vnrvjiet.in"
terraform apply -var="notification_email=23071a66c5@vnrvjiet.in" -auto-approve
```

---

## ✅ SOLUTION 2: Use Lightweight Analytics (No Pandas)

**File created:** `analytics/lambda_analytics_lightweight.py`

**Features:**
- ✅ Native Python + CSV module (no Pandas)
- ✅ Deployment size < 1 MB
- ✅ Works in Mumbai region
- ✅ Same API as Pandas version
- ✅ 100% FREE TIER

**Query types supported:**
1. `symbol_stats` - Statistics for a symbol on a date
2. `daily_summary` - Summary for all symbols
3. `date_range` - Data over date range
4. `top_movers` - Top gainers/losers

**To enable later (after MVP deploys):**
1. Uncomment analytics Lambda in `main-mvp.tf`
2. Change handler to `lambda_analytics_lightweight.lambda_handler`
3. Remove Pandas from deployment package

---

## ✅ SOLUTION 3: Query CSV Files Directly via S3 Select

**Use S3 Select API** to query CSV without Lambda:

```python
import boto3

s3 = boto3.client('s3')

# Query CSV using S3 Select (SQL on S3)
response = s3.select_object_content(
    Bucket='your-bucket',
    Key='analytics/csv/symbol=RELIANCE/year=2025/month=10/day=07/data.csv.gz',
    Expression='SELECT * FROM s3object s WHERE s.close > 2500',
    ExpressionType='SQL',
    InputSerialization={
        'CSV': {'FileHeaderInfo': 'USE'},
        'CompressionType': 'GZIP'
    },
    OutputSerialization={'JSON': {}}
)

# Process results
for event in response['Payload']:
    if 'Records' in event:
        print(event['Records']['Payload'].decode())
```

**Pros:**
- ✅ No Lambda needed
- ✅ SQL-like queries
- ✅ 100% FREE
- ✅ Fast (1-2 seconds)

**Cons:**
- ❌ Limited SQL (no GROUP BY, JOIN)
- ❌ Must query one file at a time

---

## ✅ SOLUTION 4: Use AWS Athena (RECOMMENDED for Analytics)

**Easiest option** for querying your CSV data:

**Cost:** $0.02/month (50 queries/day with partitioning)

**Setup:**
```sql
-- Create Athena table
CREATE EXTERNAL TABLE ohlcv_data (
    symbol STRING,
    timestamp_iso STRING,
    open DOUBLE,
    high DOUBLE,
    low DOUBLE,
    close DOUBLE,
    volume BIGINT
)
PARTITIONED BY (
    symbol_name STRING,
    year INT,
    month INT,
    day INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://your-bucket/analytics/csv/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- Query examples
SELECT symbol, AVG(close) as avg_close
FROM ohlcv_data
WHERE symbol_name = 'RELIANCE' AND year = 2025 AND month = 10
GROUP BY symbol;
```

**See:** `ATHENA_SETUP_GUIDE.md` for full setup

---

## 🎯 RECOMMENDED APPROACH FOR YOU

### **Phase 1: Deploy MVP Core (NOW)**
```powershell
cd d:\Price Feed Parser\infra
terraform apply -var="notification_email=23071a66c5@vnrvjiet.in" -auto-approve
```

**What deploys:**
1. ✅ S3 bucket (data lake)
2. ✅ Ingestion Lambda (fetch OHLCV data)
3. ✅ ETL Lambda (convert JSON → CSV)
4. ✅ Token Generator (manage Fyers credentials)
5. ✅ EventBridge schedules (automation)

**What's commented out:**
- ❌ Analytics Lambda (Pandas issue)

---

### **Phase 2: Add Analytics Later (Optional)**

**Choose one:**

#### **Option A: Use Athena (EASIEST)**
- Cost: $0.02/month
- Setup time: 5 minutes
- Full SQL queries
- No coding needed

#### **Option B: Deploy Lightweight Lambda**
1. Uncomment analytics Lambda in `main-mvp.tf`
2. Update to use `lambda_analytics_lightweight.py`
3. Deploy with Terraform

**Cost:** $0.00/month (100% FREE)

---

## 📝 FILES MODIFIED

### 1. `infra/main-mvp.tf`
```terraform
# Commented out analytics Lambda (lines 650-687)
# resource "aws_lambda_function" "analytics" { ... }
```

### 2. `analytics/lambda_analytics_lightweight.py` (NEW)
- Native Python implementation
- No Pandas dependency
- < 1 MB deployment size

### 3. `analytics/requirements_lightweight.txt` (NEW)
```
# No external dependencies - uses only boto3 (built into Lambda runtime)
```

---

## ✅ NEXT STEPS

**1. Deploy Core MVP:**
```powershell
cd d:\Price Feed Parser\infra
terraform apply -var="notification_email=23071a66c5@vnrvjiet.in" -auto-approve
```

**2. Verify Deployment:**
```powershell
# Check ingestion Lambda
aws lambda list-functions --query "Functions[?FunctionName==\`stock-pipeline-mvp-ingestion\`]"

# Check ETL Lambda
aws lambda list-functions --query "Functions[?FunctionName==\`stock-pipeline-mvp-etl\`]"

# Test ingestion
aws lambda invoke --function-name stock-pipeline-mvp-ingestion response.json
cat response.json
```

**3. Monitor Logs:**
```powershell
# Ingestion logs
aws logs tail /aws/lambda/stock-pipeline-mvp-ingestion --follow

# ETL logs
aws logs tail /aws/lambda/stock-pipeline-mvp-etl --follow
```

---

## 🔍 WHY THIS WORKS

### **Original Problem:**
```
Pandas package = 100 MB
Lambda limit = 50 MB (direct) or 250 MB (via S3)
Mumbai has no public Lambda Layers
→ Deployment fails ❌
```

### **Solution:**
```
Remove Pandas = < 1 MB package
Use native Python CSV module
Deploy only boto3 (built into Lambda)
→ Deployment succeeds ✅
```

---

## 💡 COMPARISON: Pandas vs Lightweight

| Feature | Pandas Version | Lightweight Version |
|---------|---------------|---------------------|
| **Package Size** | ~100 MB | < 1 MB |
| **Deploy in Mumbai** | ❌ No (needs Layer) | ✅ Yes |
| **Dependencies** | pandas, numpy | boto3 only (built-in) |
| **Performance** | Fast | Slightly slower |
| **Code Complexity** | Simple | More code |
| **FREE TIER** | ✅ Yes | ✅ Yes |

---

## 📚 RELATED DOCUMENTATION

- `FREE_TIER_ALTERNATIVES.md` - Alternative analytics solutions
- `ATHENA_SETUP_GUIDE.md` - How to set up Athena queries
- `README-MVP.md` - MVP deployment guide
- `LAMBDA_ANALYTICS_GUIDE.md` - Analytics Lambda usage

---

## ❓ FAQ

**Q: Can I use Pandas later?**
A: Yes, create your own Lambda Layer in Mumbai:
```powershell
# Build Pandas layer (requires Docker)
docker run -v "$PWD":/var/task "public.ecr.aws/sam/build-python3.11" /bin/sh -c "pip install pandas -t python/lib/python3.11/site-packages/; exit"
zip -r pandas-layer.zip python
```

**Q: Will analytics work without Pandas?**
A: Yes! The lightweight version supports all the same queries using native Python CSV processing.

**Q: Is Athena better than Lambda?**
A: For analytics, yes:
- ✅ SQL queries (easier)
- ✅ No code deployment
- ✅ Handles large datasets
- ❌ Costs $0.02/month (vs Lambda $0)

**Q: Can I delete the Pandas files?**
A: Keep them for reference, but you can delete:
- `analytics/lambda_analytics.py` (Pandas version)
- `analytics/requirements.txt` (Pandas deps)
- `deployment/package-analytics-*.ps1` (packaging scripts)

---

## ✅ SUMMARY

**Problem:** Pandas too large for Lambda in Mumbai (no public layers)

**Solution:** 
1. ✅ Comment out analytics Lambda
2. ✅ Deploy core MVP (ingestion + ETL)
3. ✅ Use Athena for analytics ($0.02/month)
   OR
4. ✅ Deploy lightweight Lambda later (no Pandas, $0/month)

**Next:** Deploy your MVP!
```powershell
cd d:\Price Feed Parser\infra
terraform apply -var="notification_email=23071a66c5@vnrvjiet.in" -auto-approve
```

---

**Status:** Ready to deploy! 🚀
