# Data Access API Documentation
# How Other Teams Can Fetch Data from Stock Price Feed Pipeline

## Overview

This document explains how other teams can access and integrate with the stock price data collected by our pipeline. We provide multiple access methods depending on your team's needs and technical requirements.

## Available Data Access Methods

### 1. **S3 Direct Access** (Recommended for Data Science Teams)
### 2. **REST API Endpoints** (Recommended for Applications)
### 3. **Real-time Streaming** (Recommended for Live Applications)
### 4. **Batch Data Downloads** (Recommended for Analytics)

---

## 1. S3 Direct Access

### Data Structure
```
s3://stock-pipeline-mvp-dev-ohlcv-{suffix}/
├── year=2025/
│   ├── month=08/
│   │   ├── day=29/
│   │   │   ├── hour=09/
│   │   │   │   ├── RELIANCE_20250829_0915.json
│   │   │   │   ├── TCS_20250829_0915.json
│   │   │   │   └── INFY_20250829_0915.json
│   │   │   └── hour=10/
│   │   └── day=30/
│   └── month=09/
└── latest/
    ├── RELIANCE_latest.json
    ├── TCS_latest.json
    └── INFY_latest.json
```

### Data Format (JSON)
```json
{
  "symbol": "RELIANCE",
  "timestamp": "2025-08-29T09:15:00Z",
  "ohlcv": {
    "open": 2450.50,
    "high": 2465.75,
    "low": 2448.20,
    "close": 2463.10,
    "volume": 1234567
  },
  "metadata": {
    "source": "fyers",
    "resolution": "15m",
    "currency": "INR",
    "exchange": "NSE"
  },
  "technical_indicators": {
    "sma_20": 2455.30,
    "rsi_14": 58.45,
    "bollinger_upper": 2480.50,
    "bollinger_lower": 2430.20
  }
}
```

### Access via AWS CLI
```bash
# List available data
aws s3 ls s3://stock-pipeline-mvp-dev-ohlcv-{suffix}/latest/

# Download latest data for specific symbol
aws s3 cp s3://stock-pipeline-mvp-dev-ohlcv-{suffix}/latest/RELIANCE_latest.json ./

# Download historical data for date range
aws s3 sync s3://stock-pipeline-mvp-dev-ohlcv-{suffix}/year=2025/month=08/ ./data/
```

### Access via Python (boto3)
```python
import boto3
import json
from datetime import datetime

class StockDataClient:
    def __init__(self, bucket_name, region='ap-south-1'):
        self.s3 = boto3.client('s3', region_name=region)
        self.bucket = bucket_name
    
    def get_latest_price(self, symbol):
        """Get latest price for a symbol"""
        key = f"latest/{symbol}_latest.json"
        try:
            response = self.s3.get_object(Bucket=self.bucket, Key=key)
            return json.loads(response['Body'].read())
        except Exception as e:
            print(f"Error fetching {symbol}: {e}")
            return None
    
    def get_historical_data(self, symbol, date, hour=None):
        """Get historical data for specific date/hour"""
        year, month, day = date.strftime('%Y'), date.strftime('%m'), date.strftime('%d')
        
        if hour:
            key = f"year={year}/month={month}/day={day}/hour={hour:02d}/{symbol}_{date.strftime('%Y%m%d')}_{hour:02d}15.json"
        else:
            # List all hours for the day
            prefix = f"year={year}/month={month}/day={day}/"
            files = self._list_files(prefix, symbol)
            return [self._get_file(f) for f in files]
        
        return self._get_file(key)
    
    def _list_files(self, prefix, symbol):
        """List files matching pattern"""
        response = self.s3.list_objects_v2(
            Bucket=self.bucket,
            Prefix=prefix
        )
        return [obj['Key'] for obj in response.get('Contents', []) 
                if symbol in obj['Key']]
    
    def _get_file(self, key):
        """Get single file"""
        try:
            response = self.s3.get_object(Bucket=self.bucket, Key=key)
            return json.loads(response['Body'].read())
        except Exception as e:
            print(f"Error fetching {key}: {e}")
            return None

# Usage Example
client = StockDataClient('stock-pipeline-mvp-dev-ohlcv-a1b2c3d4')

# Get latest prices
reliance_data = client.get_latest_price('RELIANCE')
print(f"RELIANCE Current Price: ₹{reliance_data['ohlcv']['close']}")

# Get historical data
from datetime import datetime
historical = client.get_historical_data('RELIANCE', datetime(2025, 8, 29))
```

---

## 2. REST API Endpoints

### API Gateway Setup (Future Enhancement)
*Note: This would require additional Lambda functions and API Gateway setup*

```yaml
# Proposed API Endpoints
GET /api/v1/stocks/{symbol}/latest
GET /api/v1/stocks/{symbol}/history?date=YYYY-MM-DD&hour=HH
GET /api/v1/stocks/latest  # All symbols
GET /api/v1/stocks/search?pattern={regex}
POST /api/v1/stocks/batch  # Batch request
```

### Sample API Response
```json
{
  "status": "success",
  "timestamp": "2025-08-29T09:15:00Z",
  "data": {
    "symbol": "RELIANCE",
    "price": {
      "current": 2463.10,
      "change": 12.60,
      "change_percent": 0.51,
      "open": 2450.50,
      "high": 2465.75,
      "low": 2448.20,
      "volume": 1234567
    },
    "indicators": {
      "rsi": 58.45,
      "sma_20": 2455.30,
      "trend": "bullish"
    }
  },
  "metadata": {
    "data_age_seconds": 45,
    "next_update": "2025-08-29T09:30:00Z",
    "source": "fyers_api"
  }
}
```

---

## 3. Real-time Streaming Access

### SNS Topic Subscription
```python
import boto3
import json

class RealTimeStockStream:
    def __init__(self, topic_arn, region='ap-south-1'):
        self.sns = boto3.client('sns', region_name=region)
        self.topic_arn = topic_arn
    
    def subscribe_email(self, email):
        """Subscribe to email notifications"""
        response = self.sns.subscribe(
            TopicArn=self.topic_arn,
            Protocol='email',
            Endpoint=email
        )
        return response['SubscriptionArn']
    
    def subscribe_sqs(self, queue_arn):
        """Subscribe SQS queue for programmatic access"""
        response = self.sns.subscribe(
            TopicArn=self.topic_arn,
            Protocol='sqs',
            Endpoint=queue_arn
        )
        return response['SubscriptionArn']

# Usage
stream = RealTimeStockStream('arn:aws:sns:ap-south-1:123456789012:stock-pipeline-mvp-alerts')
subscription = stream.subscribe_email('your-team@company.com')
```

### EventBridge Integration
```python
import boto3

def setup_eventbridge_rule(rule_name, target_lambda_arn):
    """Set up EventBridge rule to trigger on data updates"""
    events = boto3.client('events', region_name='ap-south-1')
    
    # Create rule
    events.put_rule(
        Name=rule_name,
        EventPattern=json.dumps({
            "source": ["stock.pipeline"],
            "detail-type": ["Stock Data Updated"],
            "detail": {
                "symbol": {"exists": True}
            }
        }),
        State='ENABLED'
    )
    
    # Add target
    events.put_targets(
        Rule=rule_name,
        Targets=[
            {
                'Id': '1',
                'Arn': target_lambda_arn
            }
        ]
    )
```

---

## 4. Batch Data Downloads

### Daily Data Export
```python
import boto3
from datetime import datetime, timedelta
import pandas as pd

class BatchDataExporter:
    def __init__(self, bucket_name, region='ap-south-1'):
        self.s3 = boto3.client('s3', region_name=region)
        self.bucket = bucket_name
    
    def export_daily_data(self, date, symbols=None, format='csv'):
        """Export full day data for analysis"""
        year, month, day = date.strftime('%Y'), date.strftime('%m'), date.strftime('%d')
        prefix = f"year={year}/month={month}/day={day}/"
        
        all_data = []
        response = self.s3.list_objects_v2(Bucket=self.bucket, Prefix=prefix)
        
        for obj in response.get('Contents', []):
            if symbols and not any(symbol in obj['Key'] for symbol in symbols):
                continue
                
            file_data = self._get_file(obj['Key'])
            if file_data:
                all_data.append(file_data)
        
        if format == 'csv':
            return self._to_dataframe(all_data)
        return all_data
    
    def _to_dataframe(self, data):
        """Convert to pandas DataFrame"""
        rows = []
        for item in data:
            row = {
                'symbol': item['symbol'],
                'timestamp': item['timestamp'],
                'open': item['ohlcv']['open'],
                'high': item['ohlcv']['high'],
                'low': item['ohlcv']['low'],
                'close': item['ohlcv']['close'],
                'volume': item['ohlcv']['volume'],
                'rsi': item.get('technical_indicators', {}).get('rsi_14'),
                'sma_20': item.get('technical_indicators', {}).get('sma_20')
            }
            rows.append(row)
        
        return pd.DataFrame(rows)
    
    def _get_file(self, key):
        """Get file content"""
        try:
            response = self.s3.get_object(Bucket=self.bucket, Key=key)
            return json.loads(response['Body'].read())
        except:
            return None

# Usage
exporter = BatchDataExporter('stock-pipeline-mvp-dev-ohlcv-a1b2c3d4')
df = exporter.export_daily_data(
    date=datetime(2025, 8, 29),
    symbols=['RELIANCE', 'TCS', 'INFY'],
    format='csv'
)

# Save to CSV
df.to_csv('stock_data_20250829.csv', index=False)
```

---

## Integration Examples

### 1. Trading Algorithm Integration
```python
import asyncio
from datetime import datetime

class TradingBot:
    def __init__(self, data_client):
        self.data_client = data_client
        self.positions = {}
    
    async def monitor_stocks(self, symbols):
        """Monitor stocks and execute trading logic"""
        while True:
            for symbol in symbols:
                data = self.data_client.get_latest_price(symbol)
                if data:
                    await self.analyze_and_trade(symbol, data)
            
            await asyncio.sleep(60)  # Check every minute
    
    async def analyze_and_trade(self, symbol, data):
        """Simple trading logic example"""
        price = data['ohlcv']['close']
        rsi = data.get('technical_indicators', {}).get('rsi_14', 50)
        
        if rsi < 30 and symbol not in self.positions:
            # Oversold - consider buying
            print(f"BUY Signal for {symbol} at ₹{price} (RSI: {rsi})")
            self.positions[symbol] = price
        
        elif rsi > 70 and symbol in self.positions:
            # Overbought - consider selling
            entry_price = self.positions[symbol]
            profit = price - entry_price
            print(f"SELL Signal for {symbol} at ₹{price} (Profit: ₹{profit})")
            del self.positions[symbol]

# Usage
bot = TradingBot(StockDataClient('bucket-name'))
asyncio.run(bot.monitor_stocks(['RELIANCE', 'TCS']))
```

### 2. Dashboard Integration
```python
import streamlit as st
import plotly.graph_objects as go
from datetime import datetime, timedelta

class StockDashboard:
    def __init__(self, data_client):
        self.client = data_client
    
    def create_dashboard(self):
        st.title("Stock Price Dashboard")
        
        # Sidebar for symbol selection
        symbols = ['RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'ICICIBANK']
        selected_symbol = st.sidebar.selectbox("Select Symbol", symbols)
        
        # Get latest data
        latest = self.client.get_latest_price(selected_symbol)
        if latest:
            # Display current price
            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Current Price", f"₹{latest['ohlcv']['close']}")
            with col2:
                st.metric("Volume", f"{latest['ohlcv']['volume']:,}")
            with col3:
                rsi = latest.get('technical_indicators', {}).get('rsi_14', 'N/A')
                st.metric("RSI", rsi)
            
            # Historical chart
            self.plot_historical_chart(selected_symbol)
    
    def plot_historical_chart(self, symbol):
        # Get last 5 days of data
        historical_data = []
        for i in range(5):
            date = datetime.now() - timedelta(days=i)
            data = self.client.get_historical_data(symbol, date)
            if data:
                historical_data.extend(data if isinstance(data, list) else [data])
        
        if historical_data:
            # Create candlestick chart
            fig = go.Figure(data=go.Candlestick(
                x=[item['timestamp'] for item in historical_data],
                open=[item['ohlcv']['open'] for item in historical_data],
                high=[item['ohlcv']['high'] for item in historical_data],
                low=[item['ohlcv']['low'] for item in historical_data],
                close=[item['ohlcv']['close'] for item in historical_data]
            ))
            
            fig.update_layout(title=f"{symbol} Price Chart")
            st.plotly_chart(fig)

# Run dashboard
# streamlit run dashboard.py
```

### 3. Alert System Integration
```python
import requests
import json

class AlertSystem:
    def __init__(self, data_client, webhook_url=None):
        self.client = data_client
        self.webhook_url = webhook_url
        self.alert_rules = {}
    
    def add_price_alert(self, symbol, condition, threshold):
        """Add price-based alert"""
        self.alert_rules[f"{symbol}_{condition}"] = {
            'symbol': symbol,
            'condition': condition,  # 'above', 'below'
            'threshold': threshold,
            'triggered': False
        }
    
    def check_alerts(self):
        """Check all active alerts"""
        for rule_id, rule in self.alert_rules.items():
            if rule['triggered']:
                continue
                
            data = self.client.get_latest_price(rule['symbol'])
            if not data:
                continue
            
            current_price = data['ohlcv']['close']
            
            if (rule['condition'] == 'above' and current_price > rule['threshold']) or \
               (rule['condition'] == 'below' and current_price < rule['threshold']):
                self.trigger_alert(rule, current_price)
                rule['triggered'] = True
    
    def trigger_alert(self, rule, current_price):
        """Send alert notification"""
        message = f"🚨 ALERT: {rule['symbol']} is {rule['condition']} ₹{rule['threshold']} (Current: ₹{current_price})"
        
        if self.webhook_url:
            # Send to Slack/Teams/Discord
            payload = {
                'text': message,
                'channel': '#trading-alerts'
            }
            requests.post(self.webhook_url, json=payload)
        
        print(message)

# Usage
alerts = AlertSystem(StockDataClient('bucket-name'), 'https://hooks.slack.com/...')
alerts.add_price_alert('RELIANCE', 'above', 2500)
alerts.add_price_alert('TCS', 'below', 3000)

# Run periodically
import time
while True:
    alerts.check_alerts()
    time.sleep(300)  # Check every 5 minutes
```

---

## Access Credentials & Permissions

### Required AWS Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::stock-pipeline-mvp-dev-ohlcv-*",
                "arn:aws:s3:::stock-pipeline-mvp-dev-ohlcv-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Subscribe",
                "sns:Unsubscribe"
            ],
            "Resource": "arn:aws:sns:ap-south-1:*:stock-pipeline-mvp-alerts"
        }
    ]
}
```

### Environment Variables
```bash
# Required for access
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-south-1"
export STOCK_DATA_BUCKET="stock-pipeline-mvp-dev-ohlcv-{suffix}"
export SNS_TOPIC_ARN="arn:aws:sns:ap-south-1:123456789012:stock-pipeline-mvp-alerts"
```

---

## Rate Limits & Best Practices

### Rate Limits
- **S3 Access**: 5,500 GET requests per second per prefix
- **SNS**: 300 transactions per second
- **Data Updates**: Every 15 minutes during market hours

### Best Practices
1. **Cache frequently accessed data** locally
2. **Use batch requests** when possible
3. **Implement exponential backoff** for retries
4. **Monitor your AWS costs** - S3 requests are charged
5. **Use appropriate data formats** (Parquet for large datasets)
6. **Implement data validation** before processing
7. **Set up monitoring** for your data consumers

### Sample Integration Checklist
```markdown
□ AWS credentials configured
□ Required permissions granted
□ Data access patterns identified
□ Error handling implemented
□ Monitoring/alerting set up
□ Cost estimation completed
□ Testing with sample data
□ Documentation updated
□ Team training completed
```

## Support & Contact

For integration support, please contact:
- **Technical Lead**: [your-email]
- **Data Team**: [data-team-email]
- **Documentation**: [wiki-link]
- **Issue Tracking**: [jira/github-link]

---

*Last Updated: August 29, 2025*
*Version: 1.0*
