#!/usr/bin/env python3
"""
MVP Data Visualization Script
Simple local analysis of the stock data stored in S3
Works without expensive AWS services like Athena
"""

import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import boto3
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from io import StringIO

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MVPDataAnalyzer:
    """Simple data analyzer for MVP that works with S3 JSON data"""
    
    def __init__(self, bucket_name: str):
        self.bucket_name = bucket_name
        self.s3_client = boto3.client('s3')
        
    def list_available_data(self, days_back: int = 7) -> List[str]:
        """List available data files in S3"""
        try:
            # Calculate date range
            end_date = datetime.now()
            start_date = end_date - timedelta(days=days_back)
            
            # List objects in the MVP raw data prefix
            prefix = "mvp-raw/"
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket_name,
                Prefix=prefix
            )
            
            files = []
            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']
                    if key.endswith('.json'):
                        files.append(key)
            
            logger.info(f"Found {len(files)} data files in the last {days_back} days")
            return sorted(files)
            
        except Exception as e:
            logger.error(f"Failed to list S3 data: {e}")
            return []
    
    def download_and_parse_data(self, file_keys: List[str]) -> pd.DataFrame:
        """Download and parse JSON data files into a pandas DataFrame"""
        try:
            all_records = []
            
            for key in file_keys:
                logger.info(f"Processing {key}")
                
                # Download file content
                response = self.s3_client.get_object(Bucket=self.bucket_name, Key=key)
                content = response['Body'].read().decode('utf-8')
                
                # Parse JSON
                data = json.loads(content)
                
                # Extract OHLCV records
                if 'data' in data:
                    for symbol, symbol_data in data['data'].items():
                        if 'candles' in symbol_data:
                            for candle in symbol_data['candles']:
                                record = {
                                    'symbol': symbol.replace('NSE:', '').replace('-EQ', ''),
                                    'timestamp': pd.to_datetime(candle[0], unit='s'),
                                    'open': float(candle[1]),
                                    'high': float(candle[2]),
                                    'low': float(candle[3]),
                                    'close': float(candle[4]),
                                    'volume': int(candle[5]),
                                    'file_source': key
                                }
                                all_records.append(record)
            
            # Create DataFrame
            df = pd.DataFrame(all_records)
            
            if not df.empty:
                # Sort by timestamp
                df = df.sort_values(['symbol', 'timestamp'])
                
                # Add calculated fields
                df['price_change'] = df.groupby('symbol')['close'].pct_change()
                df['price_range'] = df['high'] - df['low']
                df['typical_price'] = (df['high'] + df['low'] + df['close']) / 3
                
                logger.info(f"Created DataFrame with {len(df)} records for {df['symbol'].nunique()} symbols")
            else:
                logger.warning("No data found in the specified files")
            
            return df
            
        except Exception as e:
            logger.error(f"Failed to process data: {e}")
            return pd.DataFrame()
    
    def create_visualizations(self, df: pd.DataFrame, output_dir: str = "./mvp_charts"):
        """Create simple visualizations for MVP analysis"""
        try:
            # Create output directory
            os.makedirs(output_dir, exist_ok=True)
            
            if df.empty:
                logger.warning("No data available for visualization")
                return
            
            # Set up the plotting style
            plt.style.use('default')
            sns.set_palette("husl")
            
            # 1. Price trends for all symbols
            logger.info("Creating price trend chart...")
            plt.figure(figsize=(15, 8))
            for symbol in df['symbol'].unique()[:5]:  # Top 5 symbols
                symbol_data = df[df['symbol'] == symbol]
                plt.plot(symbol_data['timestamp'], symbol_data['close'], 
                        label=symbol, linewidth=2, alpha=0.8)
            
            plt.title('Stock Price Trends (Close Price)', fontsize=16, fontweight='bold')
            plt.xlabel('Time', fontsize=12)
            plt.ylabel('Price (₹)', fontsize=12)
            plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig(f"{output_dir}/price_trends.png", dpi=300, bbox_inches='tight')
            plt.close()
            
            # 2. Volume analysis
            logger.info("Creating volume analysis chart...")
            plt.figure(figsize=(12, 6))
            volume_by_symbol = df.groupby('symbol')['volume'].sum().sort_values(ascending=False)
            volume_by_symbol.head(10).plot(kind='bar')
            plt.title('Total Volume by Symbol', fontsize=16, fontweight='bold')
            plt.xlabel('Symbol', fontsize=12)
            plt.ylabel('Total Volume', fontsize=12)
            plt.xticks(rotation=45)
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig(f"{output_dir}/volume_analysis.png", dpi=300, bbox_inches='tight')
            plt.close()
            
            # 3. Price change distribution
            logger.info("Creating price change distribution...")
            plt.figure(figsize=(10, 6))
            price_changes = df['price_change'].dropna()
            plt.hist(price_changes, bins=50, alpha=0.7, edgecolor='black')
            plt.axvline(price_changes.mean(), color='red', linestyle='--', 
                       label=f'Mean: {price_changes.mean():.4f}')
            plt.title('Price Change Distribution', fontsize=16, fontweight='bold')
            plt.xlabel('Price Change (%)', fontsize=12)
            plt.ylabel('Frequency', fontsize=12)
            plt.legend()
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig(f"{output_dir}/price_change_distribution.png", dpi=300, bbox_inches='tight')
            plt.close()
            
            # 4. Correlation heatmap
            if len(df['symbol'].unique()) > 1:
                logger.info("Creating correlation heatmap...")
                pivot_close = df.pivot_table(values='close', index='timestamp', columns='symbol')
                correlation_matrix = pivot_close.corr()
                
                plt.figure(figsize=(10, 8))
                sns.heatmap(correlation_matrix, annot=True, cmap='coolwarm', center=0,
                           square=True, fmt='.2f')
                plt.title('Stock Price Correlation Matrix', fontsize=16, fontweight='bold')
                plt.tight_layout()
                plt.savefig(f"{output_dir}/correlation_heatmap.png", dpi=300, bbox_inches='tight')
                plt.close()
            
            # 5. Daily summary statistics
            logger.info("Creating daily summary...")
            daily_stats = df.groupby(df['timestamp'].dt.date).agg({
                'close': ['count', 'mean'],
                'volume': 'sum',
                'price_change': ['mean', 'std']
            }).round(4)
            
            # Save daily stats to CSV
            daily_stats.to_csv(f"{output_dir}/daily_statistics.csv")
            
            logger.info(f"Charts saved to {output_dir}")
            
        except Exception as e:
            logger.error(f"Failed to create visualizations: {e}")
    
    def generate_summary_report(self, df: pd.DataFrame) -> str:
        """Generate a text summary report"""
        try:
            if df.empty:
                return "No data available for analysis."
            
            report = []
            report.append("=== MVP Stock Data Analysis Report ===")
            report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            report.append("")
            
            # Basic statistics
            report.append("📊 DATA OVERVIEW:")
            report.append(f"  • Total records: {len(df):,}")
            report.append(f"  • Unique symbols: {df['symbol'].nunique()}")
            report.append(f"  • Date range: {df['timestamp'].min().date()} to {df['timestamp'].max().date()}")
            report.append(f"  • Data points per symbol: {len(df) // df['symbol'].nunique():.0f} average")
            report.append("")
            
            # Top performers
            latest_data = df.loc[df.groupby('symbol')['timestamp'].idxmax()]
            top_gainers = latest_data.nlargest(5, 'price_change')
            top_losers = latest_data.nsmallest(5, 'price_change')
            
            report.append("📈 TOP GAINERS (Latest Period):")
            for _, row in top_gainers.iterrows():
                if pd.notna(row['price_change']):
                    report.append(f"  • {row['symbol']}: {row['price_change']*100:.2f}% (₹{row['close']:.2f})")
            report.append("")
            
            report.append("📉 TOP LOSERS (Latest Period):")
            for _, row in top_losers.iterrows():
                if pd.notna(row['price_change']):
                    report.append(f"  • {row['symbol']}: {row['price_change']*100:.2f}% (₹{row['close']:.2f})")
            report.append("")
            
            # Volume leaders
            volume_leaders = latest_data.nlargest(5, 'volume')
            report.append("💹 VOLUME LEADERS:")
            for _, row in volume_leaders.iterrows():
                report.append(f"  • {row['symbol']}: {row['volume']:,} shares")
            report.append("")
            
            # Market statistics
            report.append("📋 MARKET STATISTICS:")
            avg_price = df['close'].mean()
            avg_volume = df['volume'].mean()
            avg_volatility = df['price_range'].mean()
            
            report.append(f"  • Average close price: ₹{avg_price:.2f}")
            report.append(f"  • Average volume: {avg_volume:,.0f} shares")
            report.append(f"  • Average price range: ₹{avg_volatility:.2f}")
            report.append(f"  • Market volatility: {df['price_change'].std()*100:.2f}%")
            report.append("")
            
            report.append("⚠️  MVP LIMITATIONS:")
            report.append("  • Limited to 10 stocks for cost optimization")
            report.append("  • 15-minute intervals only")
            report.append("  • Basic analysis (no advanced indicators)")
            report.append("  • Local processing (no cloud analytics)")
            report.append("")
            
            report.append("🚀 TO SCALE UP:")
            report.append("  • Enable RDS for structured data storage")
            report.append("  • Add AWS Glue for advanced ETL")
            report.append("  • Use Athena for SQL analytics")
            report.append("  • Implement real-time streaming")
            
            return "\n".join(report)
            
        except Exception as e:
            logger.error(f"Failed to generate summary report: {e}")
            return f"Report generation failed: {e}"

def main():
    """Main analysis workflow"""
    try:
        # Configuration
        bucket_name = os.getenv('S3_BUCKET_NAME')
        if not bucket_name:
            logger.error("S3_BUCKET_NAME environment variable not set")
            sys.exit(1)
        
        # Initialize analyzer
        analyzer = MVPDataAnalyzer(bucket_name)
        
        # List available data
        data_files = analyzer.list_available_data(days_back=7)
        
        if not data_files:
            logger.warning("No data files found. Make sure the Lambda function has run and created data.")
            return
        
        # Process data
        df = analyzer.download_and_parse_data(data_files)
        
        if df.empty:
            logger.warning("No valid data found in the files.")
            return
        
        # Create output directory
        output_dir = f"./mvp_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        os.makedirs(output_dir, exist_ok=True)
        
        # Generate visualizations
        analyzer.create_visualizations(df, output_dir)
        
        # Generate summary report
        report = analyzer.generate_summary_report(df)
        
        # Save report
        with open(f"{output_dir}/analysis_report.txt", 'w') as f:
            f.write(report)
        
        # Save raw data
        df.to_csv(f"{output_dir}/processed_data.csv", index=False)
        
        # Print summary
        print(report)
        print(f"\n📁 Analysis files saved to: {output_dir}")
        
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
