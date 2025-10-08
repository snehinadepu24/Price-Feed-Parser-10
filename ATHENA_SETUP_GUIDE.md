# Athena Table Setup Guide

## 🎯 One-Time Setup (2 minutes)

Follow these steps **after your first ETL run** to enable Athena queries.

---

## Step 1: Get Your S3 Bucket Name

```powershell
cd "d:\Price Feed Parser\infra"
$bucket = terraform output -raw s3_bucket_name
Write-Host "Your bucket name: $bucket"
```

**Copy the bucket name** - you'll need it in Step 3.

---

## Step 2: Open Athena Console

1. Go to: https://console.aws.amazon.com/athena/home?region=ap-south-1
2. Click **"Query editor"** (left sidebar)
3. If prompted about query results location:
   - Click **"Settings"** (top right)
   - Set query result location to: `s3://YOUR_BUCKET_NAME/athena-results/`
   - Click **"Save"**

---

## Step 3: Create Database

Copy and paste this into the Athena query editor:

```sql
CREATE DATABASE IF NOT EXISTS stock_analytics
COMMENT 'Stock price analytics database'
LOCATION 's3://YOUR_BUCKET_NAME/athena-database/';
```

**Replace `YOUR_BUCKET_NAME`** with your actual bucket name from Step 1.

Click **"Run"** (or press Ctrl+Enter).

**Expected output**: `Query successful`

---

## Step 4: Select the Database

In the left sidebar under **"Database"**, select **`stock_analytics`** from the dropdown.

---

## Step 5: Create the OHLCV Table

Copy the entire SQL below, **replace YOUR_BUCKET_NAME**, and run it:

```sql
-- Athena Table for Lightweight CSV ETL Output
CREATE EXTERNAL TABLE IF NOT EXISTS ohlcv_csv (
  symbol string,
  symbol_clean string,
  timestamp_unix bigint,
  timestamp_iso timestamp,
  open double,
  high double,
  low double,
  close double,
  volume bigint,
  resolution string,
  fetch_timestamp string,
  hour int,
  processed_at timestamp
)
PARTITIONED BY (
  symbol string,
  year int,
  month int,
  day int
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://YOUR_BUCKET_NAME/analytics/csv/'
TBLPROPERTIES (
  'has_encrypted_data'='false',
  'skip.header.line.count'='1',
  'compressionType'='gzip',
  'projection.enabled'='true',
  'projection.symbol.type'='enum',
  'projection.symbol.values'='RELIANCE,TCS,HDFCBANK,INFY,HINDUNILVR,ICICIBANK,KOTAKBANK,SBIN,BHARTIARTL,ITC,ASIANPAINT,LT,AXISBANK,MARUTI,SUNPHARMA,TITAN,ULTRACEMCO,NESTLEIND,WIPRO,MM',
  'projection.year.type'='integer',
  'projection.year.range'='2024,2030',
  'projection.month.type'='integer',
  'projection.month.range'='1,12',
  'projection.month.digits'='2',
  'projection.day.type'='integer',
  'projection.day.range'='1,31',
  'projection.day.digits'='2',
  'storage.location.template'='s3://YOUR_BUCKET_NAME/analytics/csv/symbol=${symbol}/year=${year}/month=${month}/day=${day}/'
);
```

Click **"Run"**.

**Expected output**: `Query successful`

---

## Step 6: Create a View (Optional but Recommended)

This creates a convenient view with calculated fields:

```sql
CREATE OR REPLACE VIEW ohlcv_view AS
SELECT 
  symbol_clean,
  timestamp_iso as timestamp,
  open,
  high,
  low,
  close,
  volume,
  resolution,
  year,
  month,
  day,
  hour,
  (close - open) as price_change,
  ((close - open) / NULLIF(open, 0)) * 100 as price_change_percent,
  (high - low) as daily_range,
  ((high - low) / NULLIF(open, 0)) * 100 as volatility_percent,
  processed_at
FROM ohlcv_csv
WHERE year >= 2025;
```

Click **"Run"**.

---

## Step 7: Test Your Table

Run this simple query to verify everything works:

```sql
SELECT * FROM ohlcv_csv LIMIT 10;
```

**Expected**: Should return rows if ETL has run, or "Zero records" if no data yet.

---

## ✅ You're Done!

Your Athena table is now set up. You can query your stock data!

---

## 📊 Sample Queries to Try

### 1. Latest Data for All Symbols
```sql
SELECT 
  symbol_clean,
  timestamp,
  close,
  volume
FROM ohlcv_view
WHERE year = 2025 
  AND month = 10 
  AND day = 7
ORDER BY timestamp DESC
LIMIT 100;
```

### 2. Daily Summary by Symbol
```sql
SELECT 
  symbol_clean,
  COUNT(*) as data_points,
  MIN(low) as day_low,
  MAX(high) as day_high,
  AVG(close) as avg_close,
  SUM(volume) as total_volume
FROM ohlcv_view
WHERE year = 2025 
  AND month = 10 
  AND day = 7
GROUP BY symbol_clean
ORDER BY total_volume DESC;
```

### 3. Top Performers
```sql
SELECT 
  symbol_clean,
  AVG(price_change_percent) as avg_change,
  MAX(price_change_percent) as max_gain,
  MIN(price_change_percent) as max_loss,
  SUM(volume) as total_volume
FROM ohlcv_view
WHERE year = 2025 
  AND month = 10
GROUP BY symbol_clean
ORDER BY avg_change DESC
LIMIT 10;
```

### 4. Query Specific Symbol
```sql
SELECT 
  timestamp,
  open,
  high,
  low,
  close,
  volume
FROM ohlcv_view
WHERE symbol_clean = 'RELIANCE'
  AND year = 2025
  AND month = 10
  AND day = 7
ORDER BY timestamp;
```

---

## 🔄 When to Update the Table

### **Add New Symbols**

When you add new stock symbols, update the projection values:

```sql
ALTER TABLE ohlcv_csv SET TBLPROPERTIES (
  'projection.symbol.values'='RELIANCE,TCS,HDFCBANK,...,NEWSYMBOL'
);
```

### **Add New Columns**

If you modify the ETL to include new fields, recreate the table:

```sql
DROP TABLE ohlcv_csv;
-- Then run CREATE TABLE again with new schema
```

---

## 🐛 Troubleshooting

### Issue: "HIVE_CURSOR_ERROR: No data found"
**Solution**: ETL hasn't run yet. Wait for first ETL execution or run manually.

### Issue: "Access Denied" on S3
**Solution**: Check Athena query result location is set to a bucket you own.

### Issue: "Table not found"
**Solution**: Make sure you selected the `stock_analytics` database in the dropdown.

### Issue: No data returned
**Solution**: 
1. Check if CSV files exist: 
   ```powershell
   aws s3 ls s3://YOUR_BUCKET/analytics/csv/ --recursive
   ```
2. Manually add partitions:
   ```sql
   MSCK REPAIR TABLE ohlcv_csv;
   ```

---

## 💡 Tips

- **Partition Projection**: Enabled by default - Athena automatically discovers partitions
- **Compression**: GZIP is automatically detected and handled
- **CSV Headers**: Skipped via `skip.header.line.count='1'`
- **Query Costs**: Minimal due to partitioning (scans only relevant files)

---

## 📋 Checklist

- [ ] Get bucket name from Terraform
- [ ] Open Athena console
- [ ] Create `stock_analytics` database
- [ ] Create `ohlcv_csv` table (with YOUR bucket name)
- [ ] Create `ohlcv_view` view
- [ ] Run test query
- [ ] Bookmark Athena console for future use

**Total time**: ~2 minutes ⏱️

---

## 🎉 Next Steps

Once setup is complete:
1. Wait for daily ETL to run (4 PM IST)
2. Check S3 for CSV files
3. Run queries in Athena
4. Build dashboards (optional)

**Questions?** Check CloudWatch logs for ETL Lambda function.
