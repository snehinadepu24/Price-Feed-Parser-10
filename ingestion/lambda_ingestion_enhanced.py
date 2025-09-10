#!/usr/bin/env python3
"""
Enhanced MVP Lambda Function for Stock Price Ingestion
Using fyers_apiv3 package (same as your working local code)
"""

import json
import logging
import os
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import boto3
from botocore.exceptions import ClientError
import pytz

# Fyers API client (same as your working code)
try:
    from fyers_apiv3 import fyersModel
    FYERS_AVAILABLE = True
except ImportError:
    FYERS_AVAILABLE = False
    logging.warning("fyers_apiv3 not available - will use demo mode")

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def is_within_trading_hours() -> bool:
    """
    Check if current time is within Indian stock market trading hours
    NSE/BSE Trading Hours: 9:15 AM - 3:30 PM IST (Monday to Friday)
    """
    try:
        # Get current time in IST
        ist = pytz.timezone('Asia/Kolkata')
        now_ist = datetime.now(ist)
        
        # Check if it's a weekday (Monday = 0, Sunday = 6)
        if now_ist.weekday() >= 5:  # Saturday or Sunday
            return False
        
        # Market hours in IST: 9:15 AM to 3:30 PM
        market_open = now_ist.replace(hour=9, minute=15, second=0, microsecond=0)
        market_close = now_ist.replace(hour=15, minute=30, second=0, microsecond=0)
        
        # Check if current time is within trading hours
        is_trading_time = market_open <= now_ist <= market_close
        
        logger.info(f"Current IST time: {now_ist.strftime('%Y-%m-%d %H:%M:%S %Z')}")
        logger.info(f"Market open: {market_open.strftime('%H:%M')} IST")
        logger.info(f"Market close: {market_close.strftime('%H:%M')} IST")
        logger.info(f"Is trading hours: {is_trading_time}")
        
        return is_trading_time
        
    except Exception as e:
        logger.warning(f"Error checking trading hours: {e}")
        return True

def lambda_handler(event, context):
    """
    AWS Lambda handler for stock data ingestion
    Enhanced version using fyers_apiv3 package (same as working local code)
    """
    try:
        logger.info("Starting Enhanced MVP stock data ingestion")
        
        # Get configuration from environment
        bucket_name = os.environ['S3_BUCKET_NAME']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        fyers_access_token_param = os.environ['FYERS_ACCESS_TOKEN_PARAM']
        fyers_client_id_param = os.environ['FYERS_CLIENT_ID_PARAM']
        environment = os.environ.get('ENVIRONMENT', 'dev')
        enable_trading_hours_check = os.environ.get('ENABLE_TRADING_HOURS_CHECK', 'true').lower() == 'true'
        
        # Initialize clients
        s3_client = boto3.client('s3')
        sns_client = boto3.client('sns')
        ssm_client = boto3.client('ssm')
        
        # Check for demo mode
        demo_mode = False
        project_name = os.environ.get('PROJECT_NAME', 'stock-pipeline-mvp')
        demo_param_name = f"/{project_name}/demo_mode"
        
        try:
            demo_param = ssm_client.get_parameter(Name=demo_param_name)
            demo_value = demo_param['Parameter']['Value']
            demo_mode = demo_value.lower() == 'true'
            logger.info(f"📋 Demo mode parameter found: '{demo_value}' -> {demo_mode}")
            if demo_mode:
                logger.info("🎬 DEMO MODE ENABLED - Using mock data")
        except ssm_client.exceptions.ParameterNotFound:
            logger.info(f"Demo mode parameter not found: {demo_param_name} - running in normal mode")
        except Exception as e:
            logger.warning(f"Could not check demo mode: {e}")
        
        # Check trading hours (unless demo mode or disabled)
        if not demo_mode and enable_trading_hours_check and not is_within_trading_hours():
            message = "⏰ Outside trading hours - skipping ingestion"
            logger.info(message)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': message,
                    'timestamp': datetime.utcnow().isoformat()
                })
            }
        
        # Get symbols
        symbols = get_mvp_symbols()
        
        # Get OHLCV data (demo mode or real API)
        if demo_mode:
            logger.info("🎬 Demo mode: Generating mock OHLCV data")
            ohlcv_data = generate_mock_ohlcv_data(symbols)
        else:
            logger.info("📊 Fetching real OHLCV data using fyers_apiv3")
            
            # Get credentials from SSM
            credentials = get_fyers_credentials_from_ssm(
                ssm_client, 
                fyers_access_token_param, 
                fyers_client_id_param
            )
            
            if not credentials:
                raise Exception("Failed to get Fyers credentials")
            
            # Fetch data using fyers_apiv3 (your working approach)
            ohlcv_data = fetch_ohlcv_data_with_fyers_api(credentials, symbols)
        
        if not ohlcv_data:
            raise Exception("Failed to fetch OHLCV data")
        
        # Store data in S3
        s3_key = store_data_in_s3(s3_client, bucket_name, ohlcv_data, environment)
        
        # Send success notification
        successful_symbols = ohlcv_data['metadata']['successful_symbols']
        total_symbols = ohlcv_data['metadata']['total_symbols_requested']
        success_rate = ohlcv_data['metadata']['success_rate_percent']
        
        message = f"✅ MVP Ingestion completed: {successful_symbols}/{total_symbols} symbols ({success_rate}% success)"
        
        send_sns_notification(sns_client, sns_topic_arn, "Stock Data Ingestion Success", message)
        
        logger.info(f"✅ {message}")
        logger.info(f"📁 Data stored at: s3://{bucket_name}/{s3_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': message,
                's3_location': f"s3://{bucket_name}/{s3_key}",
                'symbols_processed': successful_symbols,
                'total_symbols': total_symbols,
                'success_rate': success_rate,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_msg = f"💥 Lambda execution failed: {str(e)}"
        logger.error(error_msg)
        
        # Send error notification
        try:
            send_sns_notification(sns_client, sns_topic_arn, "Stock Data Ingestion Failed", error_msg)
        except:
            pass
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Ingestion failed',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def get_fyers_credentials_from_ssm(ssm_client, access_token_param: str, client_id_param: str) -> Dict[str, str]:
    """
    Get Fyers credentials from SSM (simplified for fyers_apiv3 approach)
    """
    try:
        parameter_names = [access_token_param, client_id_param]
        
        response = ssm_client.get_parameters(
            Names=parameter_names,
            WithDecryption=True
        )
        
        if len(response['Parameters']) < 2:
            missing_params = set(parameter_names) - {p['Name'] for p in response['Parameters']}
            raise ValueError(f"Missing SSM parameters: {missing_params}")
        
        credentials = {}
        for param in response['Parameters']:
            if param['Name'] == access_token_param:
                credentials['access_token'] = param['Value']
            elif param['Name'] == client_id_param:
                credentials['client_id'] = param['Value']
        
        # Validate
        if not credentials.get('access_token') or not credentials.get('client_id'):
            raise ValueError("Missing access_token or client_id")
        
        logger.info("✅ Successfully retrieved Fyers credentials from SSM")
        return credentials
        
    except Exception as e:
        logger.error(f"❌ Failed to get Fyers credentials: {e}")
        return None

def fetch_ohlcv_data_with_fyers_api(credentials: Dict[str, str], symbols: List[str]) -> Optional[Dict]:
    """
    Fetch OHLCV data using fyers_apiv3 package (same as your working local code)
    """
    try:
        if not FYERS_AVAILABLE:
            raise ImportError("fyers_apiv3 package not available")
        
        client_id = credentials['client_id']
        access_token = credentials['access_token']
        
        # Initialize Fyers client (same as your working approach)
        fyers = fyersModel.FyersModel(client_id=client_id, token=access_token, log_path="")
        logger.info("✅ Fyers client initialized successfully")
        
        # Get current date for data fetching
        today = datetime.now().strftime("%Y-%m-%d")
        
        all_data = {}
        failed_symbols = []
        successful_requests = 0
        
        logger.info(f"📊 Fetching data for {len(symbols)} symbols using fyers_apiv3")
        
        for i, symbol in enumerate(symbols):
            try:
                logger.info(f"📈 Fetching {symbol} ({i+1}/{len(symbols)})")
                
                # Use same payload structure as your working code
                payload = {
                    "symbol": symbol,
                    "resolution": "5",  # 5-minute candles (same as your working code)
                    "date_format": "1",
                    "range_from": today,
                    "range_to": today,
                    "cont_flag": "1"
                }
                
                # Call Fyers API (same as your working code)
                resp = fyers.history(payload)
                
                # Check response (same validation as your working code)
                if not isinstance(resp, dict):
                    logger.warning(f"❌ Unexpected response type for {symbol}: {type(resp)}")
                    failed_symbols.append(symbol)
                    continue
                
                if resp.get("s") == "error" or (resp.get("code") and resp.get("code") != 200):
                    logger.warning(f"❌ API Error for {symbol}: {resp}")
                    failed_symbols.append(symbol)
                    continue
                
                candles = resp.get("candles", [])\n                \n                if not candles:
                    logger.warning(f"⚠️  No candles for {symbol}")
                    failed_symbols.append(symbol)
                    continue
                \n                # Store successful data
                all_data[symbol] = {
                    'symbol': symbol,
                    'resolution': '5',
                    'candles': candles,
                    'timestamp': datetime.utcnow().isoformat(),
                    'total_records': len(candles),
                    'api_response': resp  # Include full response for debugging
                }
                
                successful_requests += 1
                logger.info(f"✅ SUCCESS: {len(candles)} candles for {symbol}")
                
                # Rate limiting (same as your working code)
                if i < len(symbols) - 1:
                    time.sleep(0.3)
                    
            except Exception as e:
                logger.error(f"❌ Exception for {symbol}: {e}")
                failed_symbols.append(symbol)
                time.sleep(0.3)
        
        success_rate = (successful_requests / len(symbols)) * 100
        logger.info(f"📊 Fyers API fetch completed: {success_rate:.1f}% success rate")
        
        return {
            'data': all_data,
            'metadata': {
                'total_symbols_requested': len(symbols),
                'successful_symbols': successful_requests,
                'failed_symbols': failed_symbols,
                'success_rate_percent': round(success_rate, 2),
                'ingestion_timestamp': datetime.utcnow().isoformat(),
                'resolution': '5',
                'api_method': 'fyers_apiv3',
                'date_fetched': today
            }
        }
        
    except Exception as e:
        logger.error(f"💥 Critical failure in Fyers API data fetching: {e}")
        return None

def get_mvp_symbols() -> List[str]:
    """Get symbol list (same symbols as your working code)"""
    mvp_symbols = [
        'NSE:RELIANCE-EQ',    # Same as your working code
        'NSE:TCS-EQ', 
        'NSE:HDFCBANK-EQ',
        'NSE:INFY-EQ',
        'NSE:ICICIBANK-EQ',
        'NSE:HINDUNILVR-EQ',
        'NSE:KOTAKBANK-EQ',
        'NSE:SBIN-EQ',
        'NSE:BHARTIARTL-EQ',
        'NSE:ITC-EQ'
    ]
    
    logger.info(f"Using MVP symbol list with {len(mvp_symbols)} symbols")
    return mvp_symbols

def generate_mock_ohlcv_data(symbols: List[str]) -> Dict:
    """Generate mock data for demo mode"""
    import random
    
    logger.info(f"🎬 Generating mock data for {len(symbols)} symbols")
    
    all_data = {}
    current_time = datetime.utcnow()
    
    for symbol in symbols:
        # Generate realistic price data
        base_price = random.uniform(100, 3000)
        
        # Generate 150 candles (similar to real trading day)
        candles = []
        for i in range(150):
            timestamp = int((current_time - timedelta(minutes=5*i)).timestamp())
            
            open_price = base_price + random.uniform(-5, 5)
            close_price = open_price + random.uniform(-10, 10)
            high_price = max(open_price, close_price) + random.uniform(0, 5)
            low_price = min(open_price, close_price) - random.uniform(0, 5)
            volume = random.randint(10000, 100000)
            
            candles.append([timestamp, open_price, high_price, low_price, close_price, volume])
        
        all_data[symbol] = {
            'symbol': symbol,
            'resolution': '5',
            'candles': candles,
            'timestamp': current_time.isoformat(),
            'total_records': len(candles),
            'mock_data': True
        }
        
        logger.info(f"✅ Generated mock data for {symbol}: {len(candles)} candles")
    
    return {
        'data': all_data,
        'metadata': {
            'total_symbols_requested': len(symbols),
            'successful_symbols': len(symbols),
            'failed_symbols': [],
            'success_rate_percent': 100.0,
            'ingestion_timestamp': current_time.isoformat(),
            'resolution': '5',
            'demo_mode': True
        }
    }

def store_data_in_s3(s3_client, bucket_name: str, data: Dict, environment: str) -> str:
    """Store OHLCV data in S3 with proper partitioning"""
    try:
        current_time = datetime.utcnow()
        
        # Create partition structure
        year = current_time.strftime('%Y')
        month = current_time.strftime('%m')
        day = current_time.strftime('%d')
        timestamp = current_time.strftime('%Y%m%d_%H%M%S')
        
        # S3 key with partitioning
        s3_key = f"mvp-raw/year={year}/month={month}/day={day}/ohlcv_mvp_{timestamp}.json"
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(data, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"📁 Data stored in S3: {s3_key}")
        return s3_key
        
    except Exception as e:
        logger.error(f"💥 Failed to store data in S3: {e}")
        raise

def send_sns_notification(sns_client, topic_arn: str, subject: str, message: str):
    """Send SNS notification"""
    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
        logger.info(f"📧 SNS notification sent: {subject}")
    except Exception as e:
        logger.error(f"💥 Failed to send SNS notification: {e}")
