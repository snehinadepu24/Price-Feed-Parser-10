#!/bin/bash
set -e

echo "🧪 Testing AWS Stock Pipeline..."

# Get Terraform outputs
cd infra
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name || echo "")
TASK_DEFINITION=$(terraform output -raw ecs_task_definition_arn || echo "")
SUBNET_ID=$(terraform output -raw private_subnet_ids | jq -r '.[0]' || echo "")
SECURITY_GROUP=$(terraform output -raw ecs_security_group_id || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name || echo "")

if [ -z "$CLUSTER_NAME" ] || [ -z "$TASK_DEFINITION" ]; then
    echo "❌ Could not get ECS cluster or task definition. Make sure infrastructure is deployed."
    exit 1
fi

echo "🏃 Running manual ingestion test..."

# Run ECS task manually
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition $TASK_DEFINITION \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "📋 Task started: $TASK_ARN"
echo "⏳ Waiting for task to complete..."

# Wait for task to complete
aws ecs wait tasks-stopped --cluster $CLUSTER_NAME --tasks $TASK_ARN

# Check task status
TASK_STATUS=$(aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks $TASK_ARN \
    --query 'tasks[0].lastStatus' \
    --output text)

echo "📊 Task status: $TASK_STATUS"

# Check logs
echo "📝 Recent logs:"
aws logs tail /ecs/stock-pipeline-ingestion --since 5m

# Check S3 for new data
echo "📁 Checking S3 for new data..."
TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)

S3_PATH="s3://$S3_BUCKET/raw/yyyy=$YEAR/mm=$MONTH/dd=$DAY/"
echo "🔍 Looking in: $S3_PATH"

FILE_COUNT=$(aws s3 ls $S3_PATH --recursive | wc -l || echo "0")
echo "📄 Files found: $FILE_COUNT"

if [ "$FILE_COUNT" -gt "0" ]; then
    echo "✅ Test successful! Data found in S3."
    aws s3 ls $S3_PATH --recursive --human-readable | head -5
else
    echo "⚠️  No data found. Check logs for errors."
fi

echo "🏁 Test completed!"