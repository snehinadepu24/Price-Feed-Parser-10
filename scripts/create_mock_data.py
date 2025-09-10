#!/usr/bin/env python3
"""
Mock Data Generator for Demo
Creates sample OHLCV data and uploads to S3 for demo purposes
"""

import boto3
import json
import subprocess
from datetime import datetime
import random

def get_bucket_name():
    """Get bucket name from Terraform output"""
    try:
        result = subprocess.run(['terraform', 'output', '-raw', 's3_bucket_name'], 
                              capture_output=True, text=True, cwd='../infra')
        if result.returncode == 0:
            return result.stdout.strip()
    except:
        pass
    return None

def generate_mock_data():
    """Generate realistic mock OHLCV data"""
    symbols = [
        "RELIANCE", "TCS", "HDFCBANK", "INFY", "HINDUNILVR",
        "ICICIBANK", "KOTAKBANK", "ITC", "LT", "SBIN",
        "BHARTIARTL", "ASIANPAINT", "AXISBANK", "MARUTI", "NESTLEIND"
    ]
    
    data = {}
    for symbol in symbols:
        base_price = random.uniform(100, 3000)
        high = base_price * random.uniform(1.01, 1.05)
        low = base_price * random.uniform(0.95, 0.99)
        close = random.uniform(low, high)
        volume = random.randint(10000, 1000000)
        change = close - base_price
        change_percent = (change / base_price) * 100
        
        data[symbol] = {
            "o": round(base_price, 2),
            "h": round(high, 2),
            "l": round(low, 2),
            "c": round(close, 2),
            "ltp": round(close, 2),
            "v": volume,
            "ch": round(change, 2),
            "chp": round(change_percent, 2)
        }
    
    return {
        "data": data,
        "metadata": {
            "timestamp": datetime.now().isoformat(),
            "total_symbols_requested": len(symbols),
            "successful_symbols": len(symbols),
            "failed_symbols": 0,
            "data_source": "DEMO_MOCK_DATA",
            "demo_mode": True
        }
    }

def upload_mock_data(bucket_name, data):
    """Upload mock data to S3"""
    s3_client = boto3.client('s3')
    
    # Create S3 key with current date/time
    now = datetime.now()
    key = f"ohlcv/{now.year}/{now.month:02d}/{now.day:02d}/mock_data_{now.strftime('%H%M%S')}.json"
    
    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(data, indent=2),
            ContentType='application/json'
        )
        print(f"✅ Mock data uploaded to: s3://{bucket_name}/{key}")
        return True
    except Exception as e:
        print(f"❌ Failed to upload mock data: {e}")
        return False

def main():
    print("🎭 Creating Mock Data for Demo")
    print("=" * 40)
    
    # Get bucket name
    bucket_name = get_bucket_name()
    if not bucket_name:
        print("❌ Could not get bucket name. Make sure Terraform is applied.")
        return
    
    print(f"📦 Using bucket: {bucket_name}")
    
    # Generate mock data
    print("📊 Generating mock OHLCV data...")
    mock_data = generate_mock_data()
    
    # Upload to S3
    print("🚀 Uploading to S3...")
    success = upload_mock_data(bucket_name, mock_data)
    
    if success:
        print("\n🎉 Mock data created successfully!")
        print("\nNow you can:")
        print("1. Refresh your dashboard: http://localhost:5000")
        print("2. Run: python scripts/fetch_data.py")
        print("3. Show S3 console with the new data files")
        
        # Show sample data
        print(f"\n📈 Sample Data Preview:")
        for symbol, values in list(mock_data['data'].items())[:5]:
            print(f"   {symbol}: ₹{values['ltp']} (Change: {values['chp']:+.2f}%)")
        print(f"   ... and {len(mock_data['data']) - 5} more symbols")
    
    print("\n🧹 To clean up later, just delete the files from S3")

if __name__ == "__main__":
    main()
