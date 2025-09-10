#!/usr/bin/env python3
"""
API Handler Lambda Function for Stock Data Service
Provides REST API endpoints for other teams to consume OHLCV data
"""

import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import os
from botocore.exceptions import ClientError, NoCredentialsError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main Lambda handler for API Gateway requests
    """
    try:
        # Extract request information
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        path_parameters = event.get('pathParameters') or {}
        query_parameters = event.get('queryStringParameters') or {}
        
        logger.info(f"📡 API Request: {http_method} {path}")
        logger.info(f"🔍 Query params: {query_parameters}")
        logger.info(f"📍 Path params: {path_parameters}")
        
        # Route to appropriate handler
        if path.startswith('/symbols'):
            return handle_symbols(query_parameters)
        elif path.startswith('/ohlcv/'):
            symbol = path_parameters.get('symbol')
            return handle_ohlcv(symbol, query_parameters)
        elif path.startswith('/latest'):
            return handle_latest(query_parameters)
        elif path.startswith('/historical'):
            return handle_historical(query_parameters)
        else:
            return create_response(404, {
                'error': 'Endpoint not found',
                'available_endpoints': {
                    '/symbols': 'List all available symbols',
                    '/ohlcv/{symbol}': 'Get OHLCV data for specific symbol',
                    '/latest': 'Get latest data for symbols',
                    '/historical': 'Get historical data'
                }
            })
            
    except Exception as e:
        logger.error(f"❌ API Error: {str(e)}")
        return create_response(500, {
            'error': 'Internal server error',
            'message': str(e)
        })

def handle_symbols(query_params: Dict) -> Dict:
    """
    GET /symbols - List all available symbols
    Query params:
    - limit: int (optional) - Limit number of symbols returned
    """
    try:
        s3_client = boto3.client('s3')
        bucket_name = os.environ['S3_BUCKET_NAME']
        
        # Get list of unique symbols from S3 files
        symbols = get_available_symbols(s3_client, bucket_name)
        
        # Apply limit if specified
        limit = query_params.get('limit')
        if limit:
            try:
                limit = int(limit)
                symbols = symbols[:limit]
            except ValueError:
                return create_response(400, {
                    'error': 'Invalid limit parameter',
                    'message': 'Limit must be a valid integer'
                })
        
        return create_response(200, {
            'symbols': symbols,
            'count': len(symbols),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
        
    except Exception as e:
        logger.error(f"❌ Error in handle_symbols: {str(e)}")
        return create_response(500, {
            'error': 'Failed to retrieve symbols',
            'message': str(e)
        })

def handle_ohlcv(symbol: str, query_params: Dict) -> Dict:
    """
    GET /ohlcv/{symbol} - Get OHLCV data for specific symbol
    Query params:
    - from: str (optional) - Start date (YYYY-MM-DD)
    - to: str (optional) - End date (YYYY-MM-DD)
    - interval: str (optional) - Time interval (5, 15, 30, 60 minutes)
    - limit: int (optional) - Limit number of candles returned
    """
    try:
        if not symbol:
            return create_response(400, {
                'error': 'Missing symbol parameter',
                'message': 'Symbol is required in the path: /ohlcv/{symbol}'
            })
        
        # Normalize symbol format
        symbol = normalize_symbol(symbol)
        
        s3_client = boto3.client('s3')
        bucket_name = os.environ['S3_BUCKET_NAME']
        
        # Parse date parameters
        from_date = query_params.get('from')
        to_date = query_params.get('to')
        interval = query_params.get('interval', '5')  # Default 5-minute
        limit = query_params.get('limit')
        
        # Get OHLCV data for symbol
        ohlcv_data = get_ohlcv_data(
            s3_client, bucket_name, symbol, 
            from_date, to_date, interval, limit
        )
        
        if not ohlcv_data:
            return create_response(404, {
                'error': 'No data found',
                'message': f'No OHLCV data found for symbol {symbol}',
                'symbol': symbol
            })
        
        return create_response(200, {
            'symbol': symbol,
            'interval': interval,
            'data': ohlcv_data,
            'count': len(ohlcv_data),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
        
    except Exception as e:
        logger.error(f"❌ Error in handle_ohlcv: {str(e)}")
        return create_response(500, {
            'error': 'Failed to retrieve OHLCV data',
            'message': str(e),
            'symbol': symbol
        })

def handle_latest(query_params: Dict) -> Dict:
    """
    GET /latest - Get latest data for all or specified symbols
    Query params:
    - symbols: str (optional) - Comma-separated list of symbols
    """
    try:
        s3_client = boto3.client('s3')
        bucket_name = os.environ['S3_BUCKET_NAME']
        
        # Parse symbols parameter
        symbols_param = query_params.get('symbols')
        if symbols_param:
            symbols = [normalize_symbol(s.strip()) for s in symbols_param.split(',')]
        else:
            symbols = get_available_symbols(s3_client, bucket_name)[:10]  # Limit to 10 for performance
        
        # Get latest data for symbols
        latest_data = get_latest_data(s3_client, bucket_name, symbols)
        
        return create_response(200, {
            'symbols': symbols,
            'data': latest_data,
            'count': len(latest_data),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
        
    except Exception as e:
        logger.error(f"❌ Error in handle_latest: {str(e)}")
        return create_response(500, {
            'error': 'Failed to retrieve latest data',
            'message': str(e)
        })

def handle_historical(query_params: Dict) -> Dict:
    """
    GET /historical - Get bulk historical data
    Query params:
    - symbol: str (optional) - Single symbol
    - symbols: str (optional) - Comma-separated list of symbols  
    - from: str (optional) - Start date (YYYY-MM-DD)
    - to: str (optional) - End date (YYYY-MM-DD)
    - format: str (optional) - Response format ('json', 'csv')
    """
    try:
        s3_client = boto3.client('s3')
        bucket_name = os.environ['S3_BUCKET_NAME']
        
        # Parse parameters
        symbol = query_params.get('symbol')
        symbols_param = query_params.get('symbols')
        from_date = query_params.get('from')
        to_date = query_params.get('to')
        format_type = query_params.get('format', 'json')
        
        # Determine symbols to fetch
        if symbol:
            symbols = [normalize_symbol(symbol)]
        elif symbols_param:
            symbols = [normalize_symbol(s.strip()) for s in symbols_param.split(',')]
        else:
            symbols = get_available_symbols(s3_client, bucket_name)[:5]  # Limit for performance
        
        # Get historical data
        historical_data = get_historical_data(
            s3_client, bucket_name, symbols, from_date, to_date
        )
        
        if format_type.lower() == 'csv':
            # Convert to CSV format
            csv_data = convert_to_csv(historical_data)
            return create_response(200, csv_data, content_type='text/csv')
        
        return create_response(200, {
            'symbols': symbols,
            'from_date': from_date,
            'to_date': to_date,
            'data': historical_data,
            'total_records': sum(len(data.get('candles', [])) for data in historical_data.values()),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
        
    except Exception as e:
        logger.error(f"❌ Error in handle_historical: {str(e)}")
        return create_response(500, {
            'error': 'Failed to retrieve historical data',
            'message': str(e)
        })

def get_available_symbols(s3_client, bucket_name: str) -> List[str]:
    """
    Get list of available symbols from S3 data
    """
    try:
        # Get the latest file to extract symbol list
        latest_file_key = get_latest_file_key(s3_client, bucket_name)
        if not latest_file_key:
            return []
        
        # Read the latest file
        response = s3_client.get_object(Bucket=bucket_name, Key=latest_file_key)
        data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Extract symbols from data structure
        symbols = []
        if 'data' in data and isinstance(data['data'], dict):
            # Old format
            symbols = list(data['data'].keys())
        else:
            # New format - symbols are direct keys
            symbols = [k for k in data.keys() if k != 'metadata']
        
        # Normalize symbol names
        symbols = [normalize_symbol(symbol) for symbol in symbols if symbol]
        return sorted(symbols)
        
    except Exception as e:
        logger.error(f"❌ Error getting available symbols: {str(e)}")
        return []

def get_latest_file_key(s3_client, bucket_name: str) -> Optional[str]:
    """
    Get the key of the most recent data file
    """
    try:
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix='mvp-raw/',
            MaxKeys=1000
        )
        
        if 'Contents' not in response:
            return None
        
        # Sort by last modified and get the latest
        files = sorted(response['Contents'], key=lambda x: x['LastModified'], reverse=True)
        return files[0]['Key'] if files else None
        
    except Exception as e:
        logger.error(f"❌ Error getting latest file: {str(e)}")
        return None

def get_ohlcv_data(s3_client, bucket_name: str, symbol: str, 
                   from_date: str = None, to_date: str = None, 
                   interval: str = '5', limit: str = None) -> List[Dict]:
    """
    Get OHLCV data for a specific symbol
    """
    try:
        # For MVP, we'll get data from recent files
        # In production, you'd implement proper date-based querying
        
        recent_files = get_recent_files(s3_client, bucket_name, days=7)
        ohlcv_candles = []
        
        for file_key in recent_files:
            try:
                response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
                data = json.loads(response['Body'].read().decode('utf-8'))
                
                # Find symbol data
                symbol_data = None
                if 'data' in data and isinstance(data['data'], dict):
                    symbol_data = data['data'].get(symbol)
                else:
                    symbol_data = data.get(symbol)
                
                if symbol_data and 'candles' in symbol_data:
                    candles = symbol_data['candles']
                    
                    # Convert candle format
                    for candle in candles:
                        if isinstance(candle, list) and len(candle) >= 6:
                            ohlcv_candles.append({
                                'timestamp': candle[0],
                                'datetime': datetime.fromtimestamp(candle[0]).isoformat() + 'Z',
                                'open': candle[1],
                                'high': candle[2],
                                'low': candle[3],
                                'close': candle[4],
                                'volume': candle[5]
                            })
                        elif isinstance(candle, dict):
                            # Already in dict format
                            ohlcv_candles.append({
                                'timestamp': candle.get('timestamp'),
                                'datetime': datetime.fromtimestamp(candle.get('timestamp', 0)).isoformat() + 'Z',
                                'open': candle.get('open'),
                                'high': candle.get('high'),
                                'low': candle.get('low'),
                                'close': candle.get('close'),
                                'volume': candle.get('volume')
                            })
                            
            except Exception as e:
                logger.warning(f"⚠️ Error processing file {file_key}: {str(e)}")
                continue
        
        # Remove duplicates and sort by timestamp
        unique_candles = {}
        for candle in ohlcv_candles:
            timestamp = candle.get('timestamp')
            if timestamp:
                unique_candles[timestamp] = candle
        
        sorted_candles = sorted(unique_candles.values(), key=lambda x: x.get('timestamp', 0))
        
        # Apply limit if specified
        if limit:
            try:
                limit_int = int(limit)
                sorted_candles = sorted_candles[-limit_int:]  # Get most recent
            except ValueError:
                pass  # Ignore invalid limit
        
        return sorted_candles
        
    except Exception as e:
        logger.error(f"❌ Error getting OHLCV data for {symbol}: {str(e)}")
        return []

def get_recent_files(s3_client, bucket_name: str, days: int = 7) -> List[str]:
    """
    Get list of recent file keys
    """
    try:
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix='mvp-raw/',
            MaxKeys=1000
        )
        
        if 'Contents' not in response:
            return []
        
        # Filter files from last N days
        cutoff_date = datetime.utcnow() - timedelta(days=days)
        recent_files = [
            obj['Key'] for obj in response['Contents']
            if obj['LastModified'].replace(tzinfo=None) >= cutoff_date
        ]
        
        return sorted(recent_files, key=lambda x: x, reverse=True)[:50]  # Limit processing
        
    except Exception as e:
        logger.error(f"❌ Error getting recent files: {str(e)}")
        return []

def get_latest_data(s3_client, bucket_name: str, symbols: List[str]) -> Dict:
    """
    Get latest data for specified symbols
    """
    try:
        latest_file_key = get_latest_file_key(s3_client, bucket_name)
        if not latest_file_key:
            return {}
        
        response = s3_client.get_object(Bucket=bucket_name, Key=latest_file_key)
        data = json.loads(response['Body'].read().decode('utf-8'))
        
        latest_data = {}
        
        for symbol in symbols:
            symbol_data = None
            if 'data' in data and isinstance(data['data'], dict):
                symbol_data = data['data'].get(symbol)
            else:
                symbol_data = data.get(symbol)
            
            if symbol_data:
                latest_data[symbol] = {
                    'symbol': symbol,
                    'latest_price': symbol_data.get('latest_price'),
                    'total_candles': symbol_data.get('total_candles'),
                    'resolution': symbol_data.get('resolution'),
                    'timestamp': symbol_data.get('timestamp'),
                    'last_candle': symbol_data.get('candles', [])[-1] if symbol_data.get('candles') else None
                }
        
        return latest_data
        
    except Exception as e:
        logger.error(f"❌ Error getting latest data: {str(e)}")
        return {}

def get_historical_data(s3_client, bucket_name: str, symbols: List[str], 
                       from_date: str = None, to_date: str = None) -> Dict:
    """
    Get historical data for specified symbols
    """
    try:
        # For MVP, get data from recent files
        recent_files = get_recent_files(s3_client, bucket_name, days=30)
        historical_data = {}
        
        for symbol in symbols:
            historical_data[symbol] = {
                'symbol': symbol,
                'candles': []
            }
        
        # Process files
        for file_key in recent_files[:20]:  # Limit processing for performance
            try:
                response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
                data = json.loads(response['Body'].read().decode('utf-8'))
                
                for symbol in symbols:
                    symbol_data = None
                    if 'data' in data and isinstance(data['data'], dict):
                        symbol_data = data['data'].get(symbol)
                    else:
                        symbol_data = data.get(symbol)
                    
                    if symbol_data and 'candles' in symbol_data:
                        historical_data[symbol]['candles'].extend(symbol_data['candles'])
                        
            except Exception as e:
                logger.warning(f"⚠️ Error processing file {file_key}: {str(e)}")
                continue
        
        # Deduplicate and sort candles for each symbol
        for symbol in historical_data:
            candles = historical_data[symbol]['candles']
            unique_candles = {}
            
            for candle in candles:
                if isinstance(candle, list) and len(candle) >= 6:
                    timestamp = candle[0]
                    unique_candles[timestamp] = {
                        'timestamp': timestamp,
                        'datetime': datetime.fromtimestamp(timestamp).isoformat() + 'Z',
                        'open': candle[1],
                        'high': candle[2],
                        'low': candle[3],
                        'close': candle[4],
                        'volume': candle[5]
                    }
            
            historical_data[symbol]['candles'] = sorted(
                unique_candles.values(), 
                key=lambda x: x['timestamp']
            )
            historical_data[symbol]['count'] = len(historical_data[symbol]['candles'])
        
        return historical_data
        
    except Exception as e:
        logger.error(f"❌ Error getting historical data: {str(e)}")
        return {}

def normalize_symbol(symbol: str) -> str:
    """
    Normalize symbol format (e.g., ensure NSE:SYMBOL-EQ format)
    """
    if not symbol:
        return symbol
    
    symbol = symbol.upper().strip()
    
    # If it's already in NSE:SYMBOL-EQ format, return as is
    if ':' in symbol and '-EQ' in symbol:
        return symbol
    
    # If it's just the symbol name, add NSE: prefix and -EQ suffix
    if ':' not in symbol:
        if not symbol.endswith('-EQ'):
            symbol = f"NSE:{symbol}-EQ"
        else:
            symbol = f"NSE:{symbol}"
    
    return symbol

def convert_to_csv(data: Dict) -> str:
    """
    Convert historical data to CSV format
    """
    try:
        csv_lines = ["symbol,timestamp,datetime,open,high,low,close,volume"]
        
        for symbol, symbol_data in data.items():
            candles = symbol_data.get('candles', [])
            for candle in candles:
                line = f"{symbol},{candle['timestamp']},{candle['datetime']},{candle['open']},{candle['high']},{candle['low']},{candle['close']},{candle['volume']}"
                csv_lines.append(line)
        
        return "\n".join(csv_lines)
        
    except Exception as e:
        logger.error(f"❌ Error converting to CSV: {str(e)}")
        return ""

def create_response(status_code: int, body: any, content_type: str = 'application/json') -> Dict:
    """
    Create standardized API Gateway response
    """
    headers = {
        'Content-Type': content_type,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
    }
    
    if content_type == 'application/json':
        body = json.dumps(body, indent=2)
    
    return {
        'statusCode': status_code,
        'headers': headers,
        'body': body
    }
