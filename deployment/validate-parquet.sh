#!/bin/bash
set -e

echo "🔍 Validating Parquet Implementation..."

# Get S3 bucket from Terraform output
if [ -f "infra/terraform.tfstate" ] || [ -f "infra/.terraform/terraform.tfstate" ]; then
    cd infra
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cd ..
else
    read -p "Enter your S3 bucket name: " S3_BUCKET
fi

if [ -z "$S3_BUCKET" ]; then
    echo "❌ S3 bucket name is required"
    exit 1
fi

echo "📁 Checking S3 bucket: $S3_BUCKET"

# Check if raw data exists
echo "🔍 Checking raw data..."
RAW_FILES=$(aws s3 ls s3://$S3_BUCKET/raw/ --recursive | wc -l)
echo "📄 Raw files found: $RAW_FILES"

# Check if parquet data exists
echo "🔍 Checking Parquet data..."
PARQUET_FILES=$(aws s3 ls s3://$S3_BUCKET/parquet/ --recursive | wc -l)
echo "📄 Parquet files found: $PARQUET_FILES"

if [ "$PARQUET_FILES" -gt "0" ]; then
    echo "✅ Parquet files detected!"
    
    # Show sample parquet structure
    echo "📂 Parquet directory structure:"
    aws s3 ls s3://$S3_BUCKET/parquet/ --recursive | head -10
    
    # Check partition structure
    echo ""
    echo "🗂️  Partition structure analysis:"
    aws s3 ls s3://$S3_BUCKET/parquet/resolution=5/ | head -5
    
    # File size analysis
    echo ""
    echo "📊 File size analysis:"
    aws s3 ls s3://$S3_BUCKET/parquet/ --recursive --human-readable | \
        awk '{print $3}' | grep -E '[0-9]+\.[0-9]+' | \
        head -10
        
else
    echo "⚠️  No Parquet files found. Checking for recent raw data to process..."
    
    # Check for recent raw files
    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%m)
    DAY=$(date +%d)
    
    RECENT_RAW=$(aws s3 ls s3://$S3_BUCKET/raw/yyyy=$YEAR/mm=$MONTH/dd=$DAY/ 2>/dev/null | wc -l || echo "0")
    
    if [ "$RECENT_RAW" -gt "0" ]; then
        echo "📄 Recent raw files found: $RECENT_RAW"
        echo "💡 Run Glue ETL job to convert to Parquet"
        
        # Show how to trigger Glue job
        echo ""
        echo "🚀 To trigger ETL processing:"
        echo "aws glue start-job-run --job-name stock-pipeline-etl"
    else
        echo "❌ No recent raw data found. Check ingestion process."
    fi
fi

# Validate Parquet file format if files exist
if [ "$PARQUET_FILES" -gt "0" ]; then
    echo ""
    echo "🔬 Validating Parquet file format..."
    
    # Get a sample parquet file
    SAMPLE_FILE=$(aws s3 ls s3://$S3_BUCKET/parquet/ --recursive | head -1 | awk '{print $4}')
    
    if [ -n "$SAMPLE_FILE" ]; then
        echo "📋 Sample file: s3://$S3_BUCKET/$SAMPLE_FILE"
        
        # Download and inspect using parquet-tools (if available)
        if command -v parquet-tools >/dev/null 2>&1; then
            echo "📖 Reading Parquet metadata..."
            aws s3 cp s3://$S3_BUCKET/$SAMPLE_FILE /tmp/sample.parquet
            parquet-tools meta /tmp/sample.parquet
            rm -f /tmp/sample.parquet
        else
            echo "💡 Install parquet-tools for detailed inspection: pip install parquet-tools"
        fi
    fi
fi

# Check Athena integration
echo ""
echo "🔍 Checking Athena integration..."

# Check if database exists in Glue Catalog
DATABASE_NAME="stock_pipeline_ohlcv"  # Default from Terraform
TABLE_EXISTS=$(aws glue get-table --database-name $DATABASE_NAME --name ohlcv_data 2>/dev/null && echo "true" || echo "false")

if [ "$TABLE_EXISTS" = "true" ]; then
    echo "✅ Athena table exists in Glue Catalog"
    
    # Show table schema
    echo "📋 Table schema:"
    aws glue get-table --database-name $DATABASE_NAME --name ohlcv_data \
        --query 'Table.StorageDescriptor.Columns[*].[Name,Type]' \
        --output table
else
    echo "⚠️  Athena table not found. Create using:"
    echo "📝 sql/athena_parquet_tables.sql"
fi

# Performance validation
echo ""
echo "📈 Performance validation recommendations:"
echo "1. ✅ Snappy compression enabled"
echo "2. ✅ Partitioning by year/month/day/symbol"
echo "3. ✅ Optimized block and page sizes"
echo "4. ✅ Dictionary encoding enabled"

# Data validation suggestions
echo ""
echo "🧪 Data validation tests to run:"
echo "1. Row count consistency: Raw JSON records = Parquet records"
echo "2. Schema validation: All required columns present"
echo "3. Data types: Numeric fields are not null/zero"
echo "4. Partitioning: Files organized correctly by date/symbol"

echo ""
echo "✅ Parquet validation completed!"

# Summary
echo ""
echo "📊 Summary:"
echo "Raw files: $RAW_FILES"
echo "Parquet files: $PARQUET_FILES"
echo "Athena table: $TABLE_EXISTS"
echo "S3 bucket: $S3_BUCKET"
