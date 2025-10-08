# API Endpoint Anomalies & Fixes Summary

## Issues Found

### 1. `/ohlcv/{symbol}` Endpoint ❌
**Location:** Lines 305-382  
**Problem:** Accepts `from` and `to` query parameters but ignores them completely

```python
# Current code (Line 315):
recent_files = get_recent_files(s3_client, bucket_name, days=7)  # HARDCODED!
```

**Impact:**
- `GET /ohlcv/TCS?from=2025-10-01&to=2025-10-08` returns last 7 days regardless of params
- Users cannot control date range
- Misleading API - parameters do nothing

---

### 2. `/historical` Endpoint ❌
**Location:** Lines 449-516  
**Problem:** Same issue - accepts date params but ignores them

```python
# Current code (Line 457):
recent_files = get_recent_files(s3_client, bucket_name, days=30)  # HARDCODED!
```

**Impact:**
- `GET /historical?symbols=TCS&from=2025-10-01&to=2025-10-08` returns last 30 days
- No date filtering applied to candles
- Very inefficient for large datasets

---

### 3. `/alfaquantz/price/get` Endpoint ⚠️
**Location:** Lines 577-663  
**Problem:** Partially works but inefficient

```python
# Current flow:
1. Converts period to from_date/to_date ✅
2. Calls get_historical_data(from_date, to_date) which IGNORES the dates ❌
3. Fetches 30 days of data
4. Filters AFTER fetching (line 620-641) ✅
```

**Impact:**
- Works but fetches way more data than needed
- Filtering happens in memory after S3 download
- Inefficient for large date ranges

---

### 4. `get_recent_files()` Function ⚠️
**Location:** Lines 384-410  
**Problem:** Only supports `days` parameter, not specific date ranges

```python
def get_recent_files(s3_client, bucket_name: str, days: int = 7) -> List[str]:
    cutoff_date = datetime.utcnow() - timedelta(days=days)
    # Filters by LastModified, not data content dates
```

**Impact:**
- Cannot fetch files for specific date ranges (e.g., Jan 2025 - March 2025)
- Uses file modification time, not data content dates
- Hardcoded 50 file limit regardless of date range

---

## Root Cause Analysis

All endpoints call `get_recent_files()` or `get_ohlcv_data()` which:
1. Accept date parameters in function signatures
2. **Never use them** in the implementation
3. Always use hardcoded `days` values instead

This is a classic **"TODO for production"** issue - the MVP shortcuts were left in place.

---

## Recommended Fixes

### Option A: Quick Fix (Filter After Fetch)
**Pros:** Simple, no S3 structure changes needed  
**Cons:** Inefficient - downloads unnecessary data

```python
def get_ohlcv_data(..., from_date: str = None, to_date: str = None):
    recent_files = get_recent_files(s3_client, bucket_name, days=30)
    
    # Parse date range
    from_ts = parse_date_to_timestamp(from_date) if from_date else 0
    to_ts = parse_date_to_timestamp(to_date) if to_date else float('inf')
    
    # Filter candles by timestamp
    filtered_candles = [
        c for c in sorted_candles 
        if from_ts <= c.get('timestamp', 0) <= to_ts
    ]
```

### Option B: Smart File Selection (Recommended)
**Pros:** Efficient - only fetches needed files  
**Cons:** Requires filename parsing or S3 metadata

```python
def get_files_by_date_range(s3_client, bucket_name, from_date, to_date):
    # List all files in prefix
    # Parse filenames like 'Raw data/Prices/ohlcv_2025-10-07_14-30-00.json'
    # Only fetch files within date range
    # Return filtered file list
```

### Option C: Use Athena/Partitioned Data (Future)
**Pros:** Optimal for large datasets  
**Cons:** Requires analytics CSV setup + Athena queries

---

## Performance Impact

### Current Behavior (7-day fetch for all requests):
- Small dataset (500 symbols × 7 days): ~50MB download per request
- API latency: 2-5 seconds
- Lambda memory: 256-512MB

### With Date Filtering:
- 1-day request: ~7MB download (86% reduction)
- 1-month request: ~210MB download
- API latency: 0.5-15 seconds (depending on range)

---

## Action Items

1. ✅ **Immediate:** Document this limitation in API docs
2. 🔧 **Short-term:** Implement Option A (filter after fetch)
3. 🚀 **Medium-term:** Implement Option B (smart file selection)
4. 📊 **Long-term:** Add Athena for complex queries

---

## Testing Checklist After Fix

```bash
# Test 1: Single day range
curl "https://API_URL/ohlcv/TCS?from=2025-10-08&to=2025-10-08"
# Should return only Oct 8 candles

# Test 2: Multi-day range  
curl "https://API_URL/ohlcv/TCS?from=2025-10-01&to=2025-10-08"
# Should return Oct 1-8 candles

# Test 3: Historical endpoint
curl "https://API_URL/historical?symbols=TCS,INFY&from=2025-10-01&to=2025-10-05"
# Should return Oct 1-5 for both symbols

# Test 4: Alfa endpoint
curl "https://API_URL/alfaquantz/price/get/tcs,5m,7d"
# Should return last 7 days (already works, but verify efficiency)

# Test 5: No date params (backward compatibility)
curl "https://API_URL/ohlcv/TCS"
# Should default to last 7 days
```

---

## Code Comment Evidence

Found in `get_ohlcv_data()` (Line 309-310):
```python
# For MVP, we'll get data from recent files
# In production, you'd implement proper date-based querying
```

This confirms it was intentionally left as a TODO! 🎯
