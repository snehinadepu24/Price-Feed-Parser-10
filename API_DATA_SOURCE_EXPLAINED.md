# 🔍 WHERE API FETCHES DATA - IMPORTANT!

## ⚠️ **API IS NOT USING ANALYTICS FOLDER**

Your API is currently fetching data from **RAW JSON files**, NOT from the **analytics CSV files**.

---

## 📂 **CURRENT DATA SOURCE**

### **API Reads From:**
```
s3://stock-pipeline-mvp-dev-ohlcv-5e23bf76/Raw data/Prices/
```

### **API Does NOT Read From:**
```
s3://stock-pipeline-mvp-dev-ohlcv-5e23bf76/analytics/csv/  ❌
```

---

## 🔧 **HOW IT WORKS NOW**

### **Code in `api_handler.py`:**

```python
# Line 287 & 389
raw_prefix = os.environ.get('S3_RAW_PREFIX', 'Raw data/Prices/')

# API queries this location:
response = s3_client.list_objects_v2(
    Bucket=bucket_name,
    Prefix='Raw data/Prices/',  # ← Reading raw JSON files
    MaxKeys=1000
)
```

### **Environment Variables (Lambda):**
```json
{
  "S3_BUCKET_NAME": "stock-pipeline-mvp-dev-ohlcv-5e23bf76",
  "PROJECT_NAME": "stock-pipeline-mvp"
  // NOTE: No S3_RAW_PREFIX set, so defaults to 'Raw data/Prices/'
}
```

---

## 📊 **DATA FLOW DIAGRAM**

```
┌─────────────────────────────────────────────────────────────────┐
│                      API REQUEST                                │
│   GET /ohlcv/RELIANCE?limit=100                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   API HANDLER LAMBDA                            │
│                 (api_handler.py)                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────┐
                    │ Reads from S3   │
                    └─────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              S3 BUCKET: Raw data/Prices/                        │
│                                                                  │
│   ✅ Raw data/Prices/2025-10-08/data_09-15-00.json             │
│   ✅ Raw data/Prices/2025-10-08/data_09-20-00.json             │
│   ✅ Raw data/Prices/2025-10-08/data_09-25-00.json             │
│                                                                  │
│   Format: Nested JSON with all symbols                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│         S3 BUCKET: analytics/csv/  (NOT USED BY API)           │
│                                                                  │
│   ❌ analytics/csv/symbol=RELIANCE/year=2025/.../data.csv.gz   │
│   ❌ analytics/csv/symbol=TCS/year=2025/.../data.csv.gz        │
│                                                                  │
│   Format: Partitioned CSV files (for Athena/analytics)         │
│   Created by: ETL Lambda (not used by API)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 **FILE FORMATS**

### **1. Raw JSON (What API Uses):**

**Location:** `Raw data/Prices/2025-10-08/data_09-15-00.json`

**Format:**
```json
{
  "data": {
    "NSE:RELIANCE-EQ": {
      "symbol": "NSE:RELIANCE-EQ",
      "candles": [
        [1728374700, 2500.0, 2520.5, 2495.0, 2515.75, 150000],
        [1728375000, 2515.75, 2525.0, 2510.0, 2520.0, 120000]
      ],
      "resolution": "5",
      "timestamp": "2025-10-08T09:15:00"
    },
    "NSE:TCS-EQ": { ... },
    "NSE:INFY-EQ": { ... }
  }
}
```

**Characteristics:**
- Contains ALL symbols in ONE file
- Nested JSON structure
- Created by ingestion Lambda
- Used by API Handler

---

### **2. Analytics CSV (NOT Used by API):**

**Location:** `analytics/csv/symbol=RELIANCE/year=2025/month=10/day=08/data.csv.gz`

**Format:**
```csv
symbol,symbol_clean,timestamp_unix,timestamp_iso,open,high,low,close,volume
NSE:RELIANCE-EQ,RELIANCE,1728374700,2025-10-08T09:15:00,2500.0,2520.5,2495.0,2515.75,150000
```

**Characteristics:**
- Partitioned by symbol (one symbol per file)
- Flat CSV structure
- GZIP compressed
- Created by ETL Lambda
- Used by Athena (for analytics queries)

---

## 🤔 **WHY API USES RAW JSON (Not CSV)**

### **Reasons:**

1. **Performance:**
   - Raw JSON has ALL symbols in one file
   - No need to list/read multiple partitioned files
   - Faster for getting multiple symbols

2. **Simplicity:**
   - Direct JSON parsing (no CSV parsing needed)
   - Native Python dict/list operations
   - Less code complexity

3. **Recent Data:**
   - Raw files are created every 5 minutes
   - More real-time than CSV (created once daily)
   - API queries last 7-30 days only

4. **MVP Design:**
   - Quick implementation
   - No external dependencies
   - Works without Athena

---

## 🔄 **TWO PARALLEL PATHS**

### **Path 1: Real-time API Queries (Current)**
```
Ingestion Lambda → Raw JSON → API Handler → REST API
                              (every 5 min)
```

### **Path 2: Analytics Queries (Optional)**
```
Ingestion Lambda → Raw JSON → ETL Lambda → CSV → Athena/Analytics
                              (daily 4 PM)
```

**They serve different purposes!**

---

## 💡 **SHOULD YOU CHANGE IT TO USE CSV?**

### **NO - Current Design is Better for API**

**Pros of Current Approach (Raw JSON):**
- ✅ **Real-time:** Updated every 5 minutes (vs CSV once daily)
- ✅ **Simpler:** One file has all symbols
- ✅ **Faster:** No need to read multiple partitioned files
- ✅ **Less code:** Direct JSON parsing

**Cons of Using CSV:**
- ❌ **Slower:** Would need to read multiple partitioned files
- ❌ **More complex:** File listing + merging logic
- ❌ **Less real-time:** CSV updated only once daily
- ❌ **More I/O:** Multiple S3 reads per query

---

## 📈 **WHEN TO USE EACH**

### **Use Raw JSON (API Handler):**
- ✅ REST API queries
- ✅ Real-time data access
- ✅ Multiple symbols in one query
- ✅ Last 7-30 days of data

### **Use CSV (Athena/Analytics):**
- ✅ Complex SQL queries (GROUP BY, AVG, SUM)
- ✅ Historical analysis
- ✅ Ad-hoc queries
- ✅ Full dataset queries

---

## 🛠️ **IF YOU WANT API TO USE CSV**

If you really want the API to read from CSV files (not recommended), here's how:

### **Option 1: Modify api_handler.py**

```python
# Change from:
raw_prefix = os.environ.get('S3_RAW_PREFIX', 'Raw data/Prices/')

# To:
csv_prefix = 'analytics/csv/'

# Then modify get_ohlcv_data() to:
def get_ohlcv_data(s3_client, bucket_name: str, symbol: str, ...):
    # List CSV files for symbol
    symbol_prefix = f'analytics/csv/symbol={symbol}/'
    response = s3_client.list_objects_v2(
        Bucket=bucket_name,
        Prefix=symbol_prefix
    )
    
    # Read each CSV file
    for obj in response.get('Contents', []):
        if obj['Key'].endswith('.csv.gz'):
            # Read and parse CSV
            csv_data = read_csv_from_s3(bucket_name, obj['Key'])
            # Process...
```

**But this would make the API:**
- ❌ Slower (multiple file reads)
- ❌ More complex (CSV parsing + decompression)
- ❌ Less real-time (CSV updated daily, not every 5 min)

---

## ✅ **RECOMMENDED SETUP**

### **Keep Current Architecture:**

```
┌──────────────────────────────────────────────────────────────┐
│                    DATA PIPELINE                             │
└──────────────────────────────────────────────────────────────┘

1. INGESTION (Every 5 min)
   Fyers API → Ingestion Lambda → Raw JSON (S3)

2. API QUERIES (Real-time)
   API Request → API Handler → Raw JSON → Response

3. ETL (Daily 4 PM)
   Raw JSON → ETL Lambda → CSV (partitioned, compressed)

4. ANALYTICS (Ad-hoc)
   Athena/S3 Select → CSV → Analytics Results
```

**This gives you:**
- ✅ Real-time API (from raw JSON)
- ✅ Efficient analytics (from partitioned CSV)
- ✅ Best of both worlds

---

## 📊 **STORAGE USAGE**

### **Current Storage:**

**Raw JSON:**
- Location: `Raw data/Prices/`
- Size: ~15 MB/day × 30 days = 450 MB/month
- Retention: 45 days (then moves to IA)
- Purpose: API queries

**Analytics CSV:**
- Location: `analytics/csv/`
- Size: ~2 MB/day × 30 days = 60 MB/month (87% compression)
- Retention: 120 days
- Purpose: Athena/analytics queries

**Total:** ~510 MB/month (well within 5 GB free tier)

---

## 🎯 **SUMMARY**

**Question:** From where is API fetching data? From S3 analytics folder?

**Answer:**
- ❌ **NO** - API is NOT using analytics folder
- ✅ **YES** - API reads from `Raw data/Prices/` (raw JSON files)

**Why?**
- Raw JSON is updated every 5 minutes (real-time)
- Contains all symbols in one file (faster queries)
- Simpler code (direct JSON parsing)
- Better for API use case

**Analytics CSV is for:**
- Athena SQL queries
- Complex analytics
- Historical analysis
- Not for real-time API queries

**Architecture is optimal - don't change it!** ✅

---

## 📚 **VERIFICATION**

### **Check what API is reading:**

```powershell
# View API handler code
Select-String -Path "d:\Price Feed Parser\api\api_handler.py" -Pattern "S3_RAW_PREFIX|Raw data"

# Check Lambda environment
aws lambda get-function-configuration --function-name stock-pipeline-mvp-api-handler --query 'Environment.Variables'

# List raw files (what API reads)
aws s3 ls "s3://stock-pipeline-mvp-dev-ohlcv-5e23bf76/Raw data/Prices/" --recursive

# List CSV files (NOT used by API)
aws s3 ls "s3://stock-pipeline-mvp-dev-ohlcv-5e23bf76/analytics/csv/" --recursive
```

---

**Your API architecture is well-designed!** 🎯
