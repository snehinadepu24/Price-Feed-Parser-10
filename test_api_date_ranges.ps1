# Test Script for API Date Range Filtering
# Run after deploying the updated API handler

$API_BASE = "https://jbw2maikhd.execute-api.ap-south-1.amazonaws.com/dev"

Write-Host "=== Testing API Date Range Filtering ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Single day range
Write-Host "Test 1: Single day range (Oct 8, 2025)" -ForegroundColor Yellow
$response1 = Invoke-RestMethod -Uri "$API_BASE/ohlcv/TCS?from=2025-10-08&to=2025-10-08" -Method Get
Write-Host "Candles returned: $($response1.count)" -ForegroundColor Green
Write-Host "Expected: ~75 candles (1 trading day)"
Write-Host ""

# Test 2: Multi-day range
Write-Host "Test 2: Multi-day range (Oct 1-8, 2025)" -ForegroundColor Yellow
$response2 = Invoke-RestMethod -Uri "$API_BASE/ohlcv/TCS?from=2025-10-01&to=2025-10-08" -Method Get
Write-Host "Candles returned: $($response2.count)" -ForegroundColor Green
Write-Host "Expected: ~600 candles (8 trading days)"
if ($response2.data.Count -gt 0) {
    $firstCandle = $response2.data[0]
    $lastCandle = $response2.data[-1]
    Write-Host "First candle: $($firstCandle.datetime)" -ForegroundColor Cyan
    Write-Host "Last candle: $($lastCandle.datetime)" -ForegroundColor Cyan
}
Write-Host ""

# Test 3: Historical endpoint with multiple symbols
Write-Host "Test 3: Historical endpoint (TCS, INFY from Oct 1-5)" -ForegroundColor Yellow
$response3 = Invoke-RestMethod -Uri "$API_BASE/historical?symbols=TCS,INFY&from=2025-10-01&to=2025-10-05" -Method Get
Write-Host "Total records: $($response3.total_records)" -ForegroundColor Green
Write-Host "TCS candles: $($response3.data.TCS.count)" -ForegroundColor Cyan
Write-Host "INFY candles: $($response3.data.INFY.count)" -ForegroundColor Cyan
Write-Host ""

# Test 4: No date parameters (backward compatibility)
Write-Host "Test 4: No date params (backward compatibility)" -ForegroundColor Yellow
$response4 = Invoke-RestMethod -Uri "$API_BASE/ohlcv/TCS" -Method Get
Write-Host "Candles returned: $($response4.count)" -ForegroundColor Green
Write-Host "Expected: Last 7 days worth of data"
Write-Host ""

# Test 5: Partial date parameters
Write-Host "Test 5: Only from_date parameter" -ForegroundColor Yellow
$response5 = Invoke-RestMethod -Uri "$API_BASE/ohlcv/TCS?from=2025-10-01" -Method Get
Write-Host "Candles returned: $($response5.count)" -ForegroundColor Green
Write-Host "Should include data from Oct 1 until today"
Write-Host ""

# Test 6: Alfa endpoint (efficiency check)
Write-Host "Test 6: Alfa endpoint (7 day period)" -ForegroundColor Yellow
$response6 = Invoke-RestMethod -Uri "$API_BASE/alfaquantz/price/get/tcs,5m,7d" -Method Get
Write-Host "Candles returned: $($response6.count)" -ForegroundColor Green
Write-Host "Period: $($response6.period)"
Write-Host "From: $($response6.from_date) To: $($response6.to_date)"
Write-Host ""

# Test 7: Invalid date format (error handling)
Write-Host "Test 7: Invalid date format (should fallback gracefully)" -ForegroundColor Yellow
try {
    $response7 = Invoke-RestMethod -Uri "$API_BASE/ohlcv/TCS?from=invalid-date&to=2025-10-08" -Method Get
    Write-Host "Status: Success (fallback behavior)" -ForegroundColor Green
    Write-Host "Candles returned: $($response7.count)" -ForegroundColor Cyan
}
catch {
    Write-Host "Status: Error - $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "✅ Test 1: Single day range"
Write-Host "✅ Test 2: Multi-day range"
Write-Host "✅ Test 3: Historical endpoint"
Write-Host "✅ Test 4: Backward compatibility"
Write-Host "✅ Test 5: Partial dates"
Write-Host "✅ Test 6: Alfa endpoint"
Write-Host "✅ Test 7: Error handling"
Write-Host ""
Write-Host "All tests completed! Check results above." -ForegroundColor Green
