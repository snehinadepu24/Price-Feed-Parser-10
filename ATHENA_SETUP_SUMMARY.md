# Athena Setup - Quick Answer

## 🎯 **YES, Manual Setup Required (But Only Once)**

**Time**: 2 minutes  
**When**: After first ETL run  
**Difficulty**: Easy (copy/paste SQL)

---

## 📋 **Setup Methods**

### **Method 1: Semi-Automated (Recommended)** ⭐

Run this PowerShell script to prepare everything:

```powershell
cd "d:\Price Feed Parser\scripts"
.\setup-athena-table.ps1
```

**What it does**:
- ✅ Gets your bucket name from Terraform
- ✅ Creates SQL with correct bucket name
- ✅ Creates Athena database automatically
- ✅ Opens Athena console in browser
- ✅ Shows you exactly what to paste

**What you do**:
- Copy the prepared SQL
- Paste into Athena console
- Click "Run"
- Done! ✨

---

### **Method 2: Fully Manual**

Follow the detailed guide:
- 📄 `ATHENA_SETUP_GUIDE.md`

**Steps**:
1. Get bucket name
2. Open Athena console
3. Create database
4. Copy SQL from `sql/athena_lightweight_csv.sql`
5. Replace `YOUR_BUCKET_NAME`
6. Run SQL
7. Test query

---

## 🤔 **Why Manual?**

### **Why Not Automated?**

1. **AWS Limitations**: Athena DDL via CLI/SDK is complex for partition projection
2. **One-time Task**: Not worth adding Lambda complexity
3. **Flexibility**: Easy to modify schema during development
4. **Visibility**: You see exactly what's created
5. **Simplicity**: No additional infrastructure needed

### **If We Automated** (not recommended):

Would need:
- ❌ Additional Lambda function
- ❌ Boto3 Athena SDK code
- ❌ Error handling logic
- ❌ IAM permissions for Athena
- ❌ More complexity for zero benefit

**ROI**: Spend 2 hours to save 2 minutes = **Not worth it!** 😄

---

## ✅ **Recommended Workflow**

### **Day 1: Deploy Infrastructure**
```powershell
cd infra
terraform apply -var="notification_email=your@email.com"
```

### **Day 1-2: Wait for First ETL Run**
- Ingestion runs every 5 minutes
- ETL runs daily at 4 PM IST
- Or trigger manually:
  ```powershell
  aws lambda invoke --function-name stock-pipeline-mvp-etl --payload '{}' response.json
  ```

### **Day 2: Setup Athena (2 minutes)**
```powershell
cd scripts
.\setup-athena-table.ps1
# Follow prompts, paste SQL into Athena console
```

### **Day 2+: Query Away!**
```sql
SELECT * FROM ohlcv_csv WHERE symbol = 'RELIANCE' LIMIT 10;
```

---

## 📊 **What Gets Created**

### **Database**: `stock_analytics`
- Logical container for tables
- Location: `s3://your-bucket/athena-database/`

### **Table**: `ohlcv_csv`
- External table pointing to S3 CSV files
- Partitioned by: symbol, year, month, day
- Partition projection enabled (automatic partition discovery)
- Compression: GZIP (automatic)

### **View**: `ohlcv_view` (optional)
- Adds calculated fields (price_change, volatility, etc.)
- Filters to 2025+ data
- Easier to query

---

## 🔄 **Future Updates**

### **Adding Symbols**
When you add new stock symbols (e.g., expanding from 30 to 500):

```sql
ALTER TABLE ohlcv_csv SET TBLPROPERTIES (
  'projection.symbol.values'='RELIANCE,TCS,HDFCBANK,...,NEWSYMBOL1,NEWSYMBOL2'
);
```

### **Schema Changes**
If you modify ETL output format:

1. Drop old table:
   ```sql
   DROP TABLE ohlcv_csv;
   ```

2. Recreate with new schema:
   ```sql
   CREATE EXTERNAL TABLE ohlcv_csv (...new columns...);
   ```

---

## 🎯 **Summary**

| Aspect | Details |
|--------|---------|
| **Frequency** | One-time setup |
| **Time Required** | 2 minutes |
| **Automation** | Semi-automated script available |
| **When to Do** | After first ETL run |
| **Difficulty** | Easy (copy/paste) |
| **Cost** | $0.00 |
| **Updates Needed** | Only when adding symbols or changing schema |

---

## 🚀 **Quick Start Commands**

```powershell
# 1. Deploy infrastructure
cd "d:\Price Feed Parser\infra"
terraform apply -var="notification_email=your@email.com"

# 2. Wait for or trigger ETL
aws lambda invoke --function-name stock-pipeline-mvp-etl --payload '{"date":"2025-10-01"}' response.json

# 3. Setup Athena (semi-automated)
cd "d:\Price Feed Parser\scripts"
.\setup-athena-table.ps1

# 4. Open Athena console (will open automatically)
# 5. Paste SQL shown by script
# 6. Click "Run"
# 7. Test query:
# SELECT * FROM ohlcv_csv LIMIT 10;
```

---

## 📚 **Documentation Files**

- 📄 `ATHENA_SETUP_GUIDE.md` - Detailed manual setup instructions
- 📄 `sql/athena_lightweight_csv.sql` - SQL template
- 📄 `scripts/setup-athena-table.ps1` - Semi-automated setup script

---

## ✨ **Bottom Line**

**Yes, you need to setup Athena table manually**, but:
- ✅ Only takes 2 minutes
- ✅ One-time setup
- ✅ Semi-automated script helps
- ✅ Better than adding complex automation
- ✅ Easy to modify if needed

**Just run the script and follow the prompts!** 🎉

---

**Next Question?** Ask about deployment! 🚀
