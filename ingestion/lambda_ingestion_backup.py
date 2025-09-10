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
    Converted to UTC: 3:45 AM - 10:00 AM UTC
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
        # If there's an error, default to allowing execution
        # This ensures the pipeline doesn't break due to timezone issues
        return True

def lambda_handler(event, context):
    """
    AWS Lambda handler for stock data ingestion
    Optimized for free tier usage with reduced API calls and simplified processing
    """
    try:
        logger.info("Starting MVP stock data ingestion")
        
        # Get configuration from environment
        bucket_name = os.environ['S3_BUCKET_NAME']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        fyers_access_token_param = os.environ['FYERS_ACCESS_TOKEN_PARAM']
        fyers_refresh_token_param = os.environ['FYERS_REFRESH_TOKEN_PARAM']
        fyers_client_id_param = os.environ['FYERS_CLIENT_ID_PARAM']
        fyers_app_secret_param = os.environ['FYERS_APP_SECRET_PARAM']
        fyers_pin_param = os.environ.get('FYERS_PIN_PARAM')  # Optional
        environment = os.environ.get('ENVIRONMENT', 'dev')
        enable_trading_hours_check = os.environ.get('ENABLE_TRADING_HOURS_CHECK', 'true').lower() == 'true'
        
        # Initialize clients
        s3_client = boto3.client('s3')
        sns_client = boto3.client('sns')
        ssm_client = boto3.client('ssm')
        
        # Check for demo mode (bypasses trading hours and API limits)
        demo_mode = False
        project_name = os.environ.get('PROJECT_NAME', 'stock-pipeline-mvp')
        demo_param_name = f"/{project_name}/demo_mode"
        logger.info(f"🔍 Checking demo mode parameter: {demo_param_name}")
        
        try:
            demo_param = ssm_client.get_parameter(Name=demo_param_name)
            demo_value = demo_param['Parameter']['Value']
            demo_mode = demo_value.lower() == 'true'
            logger.info(f"📋 Demo mode parameter found: '{demo_value}' -> {demo_mode}")
            if demo_mode:
                logger.info("🎬 DEMO MODE ENABLED - Bypassing trading hours check and using demo data")
        except ssm_client.exceptions.ParameterNotFound:
            logger.info(f"Demo mode parameter not found: {demo_param_name} - running in normal mode")
        except Exception as e:
            logger.warning(f"Could not check demo mode: {e}")
        
        # Get API credentials from SSM Parameter Store
        # In demo mode, bypass credential validation and use mock data
        if demo_mode:
            logger.info("🎬 Demo mode: Skipping credential validation, using mock data")
            credentials = {'demo': True}  # Mock credentials for demo
        else:
            credentials = get_fyers_credentials_from_ssm(
                ssm_client, 
                fyers_access_token_param,
                fyers_refresh_token_param, 
                fyers_client_id_param,
                fyers_app_secret_param,
                fyers_pin_param
            )
        
        # Check if within Indian trading hours (if enabled and not in demo mode)
        if not demo_mode and enable_trading_hours_check and not is_within_trading_hours():
            logger.info("Outside trading hours. Skipping data ingestion to save API calls.")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Skipped: Outside trading hours',
                    'timestamp': datetime.utcnow().isoformat(),
                    'next_execution': 'Will run during next trading session',
                    'trading_hours': '9:15 AM - 3:30 PM IST (Mon-Fri)'
                })
            }

        # Get limited symbol list for MVP (reduce API calls)
        symbols = get_mvp_symbol_list()
        logger.info(f"Processing {len(symbols)} symbols for MVP")
        
        # Fetch data with rate limiting
        if demo_mode:
            logger.info("🎬 Demo mode: Generating mock OHLCV data")
            ohlcv_data = generate_mock_ohlcv_data(symbols)
        else:
            ohlcv_data = fetch_ohlcv_data_mvp(credentials, symbols)
        
        if not ohlcv_data or not ohlcv_data.get('data'):
            raise Exception("No data fetched from API")
        
        # Upload to S3
        upload_success = upload_to_s3(s3_client, bucket_name, ohlcv_data)
        
        if not upload_success:
            raise Exception("Failed to upload data to S3")
        
        # Calculate metrics
        successful_symbols = ohlcv_data['metadata']['successful_symbols']
        total_symbols = ohlcv_data['metadata']['total_symbols_requested']
        success_rate = (successful_symbols / total_symbols * 100) if total_symbols > 0 else 0
        
        # Send success notification
        success_message = f"""
MVP Stock Data Ingestion - SUCCESS

Statistics:
- Symbols processed: {successful_symbols}/{total_symbols}
- Success rate: {success_rate:.1f}%
- Execution time: {datetime.utcnow().isoformat()}
- S3 bucket: {bucket_name}
- Environment: {environment}

Lambda execution details:
- Function: {context.function_name}
- Request ID: {context.aws_request_id}
- Memory used: {context.memory_limit_in_mb}MB
        """
        
        send_sns_notification(sns_client, sns_topic_arn, 
                            "MVP Stock Ingestion - Success", 
                            success_message.strip())
        
        logger.info(f"MVP ingestion completed: {successful_symbols} symbols processed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Ingestion completed successfully',
                'symbols_processed': successful_symbols,
                'total_symbols': total_symbols,
                'success_rate': success_rate,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_msg = f"MVP stock data ingestion failed: {str(e)}"
        logger.error(error_msg)
        
        # Send failure notification
        try:
            send_sns_notification(sns_client, sns_topic_arn,
                                "MVP Stock Ingestion - FAILURE",
                                f"Ingestion failed at {datetime.utcnow().isoformat()}\n\nError: {error_msg}")
        except:
            logger.error("Failed to send failure notification")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Ingestion failed',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def get_fyers_credentials_from_ssm(ssm_client, access_token_param: str, refresh_token_param: str, client_id_param: str, app_secret_param: str, pin_param: str = None) -> Dict[str, str]:
    """
    Retrieve Fyers API credentials from AWS SSM Parameter Store
    This function now implements automatic token refresh using stored refresh token
    """
    try:
        # Get stored credentials (client_id, app_secret, refresh_token, and optional PIN and access_token)
        parameter_names = [refresh_token_param, client_id_param, app_secret_param]
        if pin_param:
            parameter_names.append(pin_param)
        
        response = ssm_client.get_parameters(
            Names=parameter_names,
            WithDecryption=True  # Decrypt SecureString parameters
        )
        
        if len(response['Parameters']) < 3:  # At least client_id, app_secret, refresh_token required
            missing_params = set(parameter_names) - {p['Name'] for p in response['Parameters']}
            raise ValueError(f"Missing SSM parameters: {missing_params}")
        
        # Build base credentials dictionary
        credentials = {}
        for param in response['Parameters']:
            if param['Name'] == refresh_token_param:
                credentials['refresh_token'] = param['Value']
            elif param['Name'] == client_id_param:
                credentials['client_id'] = param['Value']
            elif param['Name'] == app_secret_param:
                credentials['app_secret'] = param['Value']
            elif param['Name'] == pin_param:
                credentials['pin'] = param['Value']
        
        # Validate required keys
        required_keys = ['refresh_token', 'client_id', 'app_secret']
        for key in required_keys:
            if key not in credentials or credentials[key] == 'CHANGE_ME':
                helpful_message = f"""
❌ SSM Parameter '{key}' is not configured properly!

To fix this, update your SSM parameters with actual Fyers API credentials:

aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/client_id" --value "YOUR_ACTUAL_CLIENT_ID" --type "SecureString" --overwrite
aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/app_secret" --value "YOUR_ACTUAL_APP_SECRET" --type "SecureString" --overwrite  
aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/refresh_token" --value "YOUR_ACTUAL_REFRESH_TOKEN" --type "SecureString" --overwrite

Get these values from your Fyers API dashboard at: https://myapi.fyers.in/dashboard/
                """
                raise ValueError(f"Invalid or placeholder credential: {key}{helpful_message}")
        
        # PIN is optional - only validate if provided
        if 'pin' in credentials and credentials['pin'] == 'CHANGE_ME':
            logger.warning("PIN parameter exists but is set to placeholder value. PIN-based operations may fail.")
        
        # Try to get existing access token first
        try:
            access_token_response = ssm_client.get_parameter(
                Name=access_token_param,
                WithDecryption=True
            )
            stored_access_token = access_token_response['Parameter']['Value']
            
            # Check if stored access token is valid (not placeholder)
            if stored_access_token != 'CHANGE_ME' and stored_access_token:
                # Test the token validity with a simple API call
                if is_access_token_valid(credentials['client_id'], stored_access_token):
                    credentials['access_token'] = stored_access_token
                    logger.info("Using valid stored access token")
                    return credentials
                else:
                    logger.info("Stored access token is invalid, refreshing...")
            else:
                logger.info("No valid access token stored, generating new one...")
                
        except ClientError as e:
            if e.response['Error']['Code'] == 'ParameterNotFound':
                logger.info("Access token parameter not found, generating new one...")
            else:
                logger.warning(f"Error retrieving access token: {e}")
        
        # Generate new access token using refresh token
        new_access_token = refresh_access_token(
            credentials['client_id'], 
            credentials['app_secret'],
            credentials['refresh_token'],
            credentials.get('pin')  # PIN is optional
        )
        
        # Store new access token in SSM for future use
        try:
            ssm_client.put_parameter(
                Name=access_token_param,
                Value=new_access_token,
                Type='SecureString',
                Overwrite=True,
                Description='Auto-refreshed Fyers access token'
            )
            logger.info("Successfully stored new access token in SSM")
        except Exception as e:
            logger.warning(f"Failed to store new access token in SSM: {e}")
            # Continue execution even if storage fails
        
        credentials['access_token'] = new_access_token
        logger.info("Successfully retrieved/refreshed Fyers API credentials")
        return credentials
        
    except ClientError as e:
        logger.error(f"Failed to retrieve SSM parameters: {e}")
        raise
    except Exception as e:
        logger.error(f"Error processing SSM parameters: {e}")
        raise

def is_access_token_valid(client_id: str, access_token: str) -> bool:
    """
    Test if the current access token is valid by making a simple API call
    Returns True if valid, False if expired or invalid
    """
    try:
        # Use production data API for token validation
        test_url = "https://api.fyers.in/data-rest/v3/profile"
        headers = {
            'Authorization': f"{client_id}:{access_token}",
            'Content-Type': 'application/json'
        }
        
        response = requests.get(test_url, headers=headers, timeout=5)
        
        # If we get a successful response, token is valid
        if response.status_code == 200:
            data = response.json()
            return data.get('code') == 200
        else:
            logger.info(f"Token validation failed with status: {response.status_code}")
            return False
            
    except Exception as e:
        logger.warning(f"Token validation error: {e}")
        return False

def refresh_access_token(client_id: str, app_secret: str, refresh_token: str, pin: str = None) -> str:
    """
    Generate a new access token using the refresh token
    This eliminates the need for daily manual login
    
    Args:
        client_id: Fyers API client ID (app ID)
        app_secret: Fyers API app secret
        refresh_token: Long-lived refresh token
        pin: Fyers trading PIN (optional, may be required for some accounts)
    
    Returns:
        New access token
    """
    import hashlib
    
    try:
        # Validate inputs (without logging sensitive data)
        if not client_id or client_id == 'CHANGE_ME':
            raise ValueError("Invalid client_id - please update SSM parameter with your actual Fyers client ID")
        if not app_secret or app_secret == 'CHANGE_ME':
            raise ValueError("Invalid app_secret - please update SSM parameter with your actual Fyers app secret")
        if not refresh_token or refresh_token == 'CHANGE_ME':
            raise ValueError("Invalid refresh_token - please update SSM parameter with your actual Fyers refresh token")
        
        # Generate appIdHash as SHA-256 of client_id + app_secret
        app_id_hash_input = f"{client_id}:{app_secret}"
        app_id_hash = hashlib.sha256(app_id_hash_input.encode()).hexdigest()
        
        # Use production auth API for token refresh
        refresh_url = "https://api.fyers.in/api/v3/validate-refresh-token"
        
        payload = {
            'grant_type': 'refresh_token',
            'appIdHash': app_id_hash,
            'refresh_token': refresh_token
        }
        
        # Add PIN if provided and valid
        if pin and pin != 'CHANGE_ME':
            payload['pin'] = pin
        
        headers = {
            'Content-Type': 'application/json'
        }
        
        logger.info("Requesting new access token using refresh token...")
        logger.info(f"Using client_id: {client_id[:4]}***{client_id[-4:] if len(client_id) > 8 else '***'}")
        logger.info(f"Generated appIdHash: {app_id_hash[:8]}...")
        
        response = requests.post(refresh_url, json=payload, headers=headers, timeout=10)
        
        # Log response details for debugging
        logger.info(f"Fyers API response status: {response.status_code}")
        try:
            response_data = response.json()
            logger.info(f"Fyers API response code: {response_data.get('code', 'N/A')}")
            if response.status_code != 200:
                logger.error(f"Fyers API error message: {response_data.get('message', 'No message')}")
        except:
            logger.error(f"Failed to parse response JSON. Raw response: {response.text[:200]}")
        
        response.raise_for_status()
        
        data = response.json()
        
        if data.get('code') == 200 and data.get('access_token'):
            logger.info("Successfully generated new access token")
            return data['access_token']
        else:
            error_msg = data.get('message', 'Unknown error during token refresh')
            error_code = data.get('code', 'Unknown')
            
            # Check if PIN is required
            if 'pin' in error_msg.lower() or error_code in [-15, -16, -17]:
                raise Exception(f"Token refresh failed (PIN may be required): {error_msg}")
            else:
                raise Exception(f"Token refresh failed: {error_msg}")
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Network error during token refresh: {e}")
        raise Exception(f"Failed to refresh access token due to network error: {e}")
    except Exception as e:
        logger.error(f"Token refresh failed: {e}")
        raise Exception(f"Failed to refresh access token: {e}")

def generate_mock_ohlcv_data(symbols: List[str]) -> Dict:
    """
    Generate realistic mock OHLCV data for demo mode
    This ensures the demo works even when API is down
    """
    import random
    
    logger.info(f"🎬 Generating mock data for {len(symbols)} symbols")
    
    all_data = {}
    current_time = datetime.utcnow()
    
    for symbol in symbols:
        # Generate realistic price data
        base_price = random.uniform(100, 3000)  # Random base price
        
        # Generate 8 candles (30 minutes of 15-min data) 
        candles = []
        for i in range(8):
            # Each candle: [timestamp, open, high, low, close, volume]
            timestamp = int((current_time - timedelta(minutes=15*i)).timestamp())
            
            open_price = base_price + random.uniform(-5, 5)
            close_price = open_price + random.uniform(-10, 10)
            high_price = max(open_price, close_price) + random.uniform(0, 5)
            low_price = min(open_price, close_price) - random.uniform(0, 5)
            volume = random.randint(10000, 100000)
            
            candles.append([timestamp, open_price, high_price, low_price, close_price, volume])
        
        all_data[symbol] = {
            'symbol': symbol,
            'resolution': '15',
            'candles': candles,
            'timestamp': current_time.isoformat(),
            'total_records': len(candles),
            'mock_data': True  # Flag to indicate this is demo data
        }
        
        logger.info(f"✅ Generated mock data for {symbol}: {len(candles)} candles")
    
    return {
        'data': all_data,
        'metadata': {
            'total_symbols_requested': len(symbols),
            'successful_symbols': len(symbols),  # All succeed in demo mode
            'failed_symbols': [],
            'success_rate_percent': 100.0,
            'ingestion_timestamp': current_time.isoformat(),
            'resolution': '15',
            'mvp_mode': True,
            'lambda_execution': True,
            'demo_mode': True,
            'data_source': 'mock_generated'
        }
    }

def get_mvp_symbol_list() -> List[str]:
    """Get a reduced list of symbols for MVP to stay within API limits"""
    # Reduced to top 10 symbols for MVP to minimize API calls
    mvp_symbols = [
        'NSE:RELIANCE-EQ',
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

def fetch_ohlcv_data_mvp(credentials: Dict[str, str], symbols: List[str]) -> Optional[Dict]:
    """
    Fetch OHLCV data with MVP optimizations:
    - Reduced symbols
    - Longer intervals between requests
    - Simple error handling
    """
    try:
        # Use production data API for OHLCV data
        base_url = "https://api.fyers.in/data-rest/v3"
        access_token = credentials['access_token']
        client_id = credentials['client_id']
        
        if not access_token:
            raise ValueError("Access token not available")
        
        # Calculate time range (last 30 minutes for MVP)
        end_time = datetime.now()
        start_time = end_time - timedelta(minutes=30)
        
        url = f"{base_url}/history"
        headers = {
            'Authorization': f"{client_id}:{access_token}",
            'Content-Type': 'application/json'
        }
        
        all_data = {}
        failed_symbols = []
        successful_requests = 0
        
        # Process symbols with longer delays to avoid rate limits
        for i, symbol in enumerate(symbols):
            try:
                logger.info(f"Fetching data for {symbol} ({i+1}/{len(symbols)})")
                
                params = {
                    'symbol': symbol,
                    'resolution': '15',  # 15-minute intervals for MVP
                    'date_format': '1',
                    'range_from': int(start_time.timestamp()),
                    'range_to': int(end_time.timestamp()),
                    'cont_flag': '1'
                }
                
                response = requests.get(url, headers=headers, params=params, timeout=10)
                response.raise_for_status()
                
                data = response.json()
                
                if data.get('code') == 200 and data.get('candles'):
                    all_data[symbol] = {
                        'symbol': symbol,
                        'resolution': '15',
                        'candles': data['candles'],
                        'timestamp': datetime.utcnow().isoformat(),
                        'total_records': len(data['candles'])
                    }
                    successful_requests += 1
                    logger.info(f"✅ Fetched {len(data['candles'])} records for {symbol}")
                else:
                    failed_symbols.append(symbol)
                    logger.warning(f"❌ No data for {symbol}: {data.get('message', 'Unknown error')}")
                
                # Rate limiting: 2 seconds between requests for MVP
                if i < len(symbols) - 1:
                    time.sleep(2)
                    
            except Exception as e:
                logger.error(f"❌ Failed to fetch {symbol}: {e}")
                failed_symbols.append(symbol)
                time.sleep(1)  # Still wait on error
        
        success_rate = (successful_requests / len(symbols)) * 100
        logger.info(f"📊 MVP fetch completed: {success_rate:.1f}% success rate")
        
        return {
            'data': all_data,
            'metadata': {
                'total_symbols_requested': len(symbols),
                'successful_symbols': successful_requests,
                'failed_symbols': failed_symbols,
                'success_rate_percent': round(success_rate, 2),
                'ingestion_timestamp': datetime.utcnow().isoformat(),
                'resolution': '15',
                'mvp_mode': True,
                'lambda_execution': True
            }
        }
        
    except Exception as e:
        logger.error(f"💥 Critical failure in MVP OHLCV data fetching: {e}")
        return None

def upload_to_s3(s3_client, bucket_name: str, data: Dict) -> bool:
    """Upload data to S3 with MVP-optimized partitioning"""
    try:
        timestamp = datetime.utcnow()
        
        # Simplified partitioning for MVP
        year = timestamp.strftime('%Y')
        month = timestamp.strftime('%m')
        day = timestamp.strftime('%d')
        
        key = f"mvp-raw/year={year}/month={month}/day={day}/ohlcv_mvp_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
        
        # Convert to JSON with compression consideration
        json_data = json.dumps(data, separators=(',', ':'))  # Compact JSON
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json_data.encode('utf-8'),
            ContentType='application/json',
            Metadata={
                'ingestion_timestamp': timestamp.isoformat(),
                'data_type': 'ohlcv_mvp_raw',
                'source': 'fyers_api_lambda',
                'symbols_count': str(data['metadata']['successful_symbols']),
                'mvp_version': 'true'
            }
        )
        
        logger.info(f"✅ Successfully uploaded MVP data to s3://{bucket_name}/{key}")
        logger.info(f"📦 Data size: {len(json_data)} bytes")
        return True
        
    except Exception as e:
        logger.error(f"❌ Failed to upload MVP data to S3: {e}")
        return False

def send_sns_notification(sns_client, topic_arn: str, subject: str, message: str) -> bool:
    """Send SNS notification for monitoring"""
    try:
        response = sns_client.publish(
            TopicArn=topic_arn,
            Subject=f"[MVP] {subject}",  # Add MVP prefix
            Message=message
        )
        logger.info(f"📧 SNS notification sent: {response.get('MessageId')}")
        return True
    except Exception as e:
        logger.error(f"❌ Failed to send SNS notification: {e}")
        return False

# For local testing
if __name__ == '__main__':
    # Mock Lambda context for local testing
    class MockContext:
        function_name = 'local-test'
        aws_request_id = 'test-request-id'
        memory_limit_in_mb = 128
    
    # Mock event
    test_event = {}
    test_context = MockContext()
    
    # Set environment variables for testing
    os.environ['S3_BUCKET_NAME'] = 'test-bucket'
    os.environ['SNS_TOPIC_ARN'] = 'arn:aws:sns:ap-south-1:123456789012:test-topic'
    os.environ['FYERS_ACCESS_TOKEN_PARAM'] = '/test/fyers/access_token'
    os.environ['FYERS_REFRESH_TOKEN_PARAM'] = '/test/fyers/refresh_token'
    os.environ['FYERS_CLIENT_ID_PARAM'] = '/test/fyers/client_id'
    os.environ['FYERS_APP_SECRET_PARAM'] = '/test/fyers/app_secret'
    os.environ['FYERS_PIN_PARAM'] = '/test/fyers/pin'  # Optional
    os.environ['ENVIRONMENT'] = 'local'
    os.environ['ENABLE_TRADING_HOURS_CHECK'] = 'true'  # Set to 'false' to disable during testing
    
    # Test trading hours function
    print(f"🕘 Current time is within trading hours: {is_within_trading_hours()}")
    print(f"📅 Current IST time: {datetime.now(pytz.timezone('Asia/Kolkata')).strftime('%Y-%m-%d %H:%M:%S %Z')}")
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))
