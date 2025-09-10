# MVP Configuration for AWS Free Tier
# This file contains only free tier services for demonstrating the MVP
# Expensive services are commented out but preserved for future use

terraform {
  required_version = ">= 1.0"
  
  # Note: For MVP, you might want to use local state instead of S3 backend
  # Comment out the backend block below and use local state for development
  /*
  backend "s3" {
    bucket         = "stock-pipeline-terraform-state"
    key            = "stock-pipeline/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
  */
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "stock-pipeline-mvp"
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
}

# Local values
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = "MVP"
  }
  
  bucket_name = "${var.project_name}-${var.environment}-ohlcv"
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

#===============================================================================
# FREE TIER SERVICES - ACTIVE FOR MVP
#===============================================================================

# S3 Bucket for data storage (Free: 5GB storage, 20,000 GET requests, 2,000 PUT requests)
resource "aws_s3_bucket" "ohlcv_data" {
  bucket = "${local.bucket_name}-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "OHLCV Data Lake - MVP"
    FreeTier = "Yes"
  })
}

resource "aws_s3_bucket_versioning" "ohlcv_data" {
  bucket = aws_s3_bucket.ohlcv_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ohlcv_data" {
  bucket = aws_s3_bucket.ohlcv_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Simplified lifecycle for MVP (keep data longer to avoid frequent transitions)
resource "aws_s3_bucket_lifecycle_configuration" "ohlcv_data" {
  bucket = aws_s3_bucket.ohlcv_data.id

  rule {
    id     = "mvp_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Keep data in standard storage longer for MVP
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90  # Shorter retention for MVP
    }
  }

  # Cleanup incomplete multipart uploads
  rule {
    id     = "cleanup_incomplete_uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# SNS Topic for notifications (Free: 1,000 notifications per month)
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SSM Parameter Store for API credentials (Free for standard parameters)
# NOTE: We only store long-lived credentials (client_id, refresh_token)
# Access tokens are generated automatically by Lambda and cached temporarily

resource "aws_ssm_parameter" "fyers_refresh_token" {
  name        = "/${var.project_name}/fyers/refresh_token"
  description = "Fyers API refresh token (long-lived, used to generate daily access tokens)"
  type        = "SecureString"
  value       = "CHANGE_ME"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "API_Credentials"
    TokenType = "LongLived"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "fyers_client_id" {
  name        = "/${var.project_name}/fyers/client_id"
  description = "Fyers API client ID"
  type        = "SecureString"
  value       = "CHANGE_ME"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "API_Credentials"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "fyers_app_secret" {
  name        = "/${var.project_name}/fyers/app_secret"
  description = "Fyers API app secret (required for appIdHash generation)"
  type        = "SecureString"
  value       = "CHANGE_ME"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "API_Credentials"
    TokenType = "LongLived"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# Optional: PIN for Fyers API (some operations may require it)
resource "aws_ssm_parameter" "fyers_pin" {
  name        = "/${var.project_name}/fyers/pin"
  description = "Fyers API PIN (optional, required for some token refresh operations)"
  type        = "SecureString"
  value       = "CHANGE_ME"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "API_Credentials"
    TokenType = "Optional"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# Optional: Access token storage for caching (will be auto-populated by Lambda)
resource "aws_ssm_parameter" "fyers_access_token" {
  name        = "/${var.project_name}/fyers/access_token"
  description = "Fyers API access token (auto-refreshed daily by Lambda)"
  type        = "SecureString"
  value       = "AUTO_GENERATED"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "API_Credentials"
    TokenType = "ShortLived"
    AutoManaged = "Yes"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# Demo mode parameter for MVP demonstrations
resource "aws_ssm_parameter" "demo_mode" {
  name        = "/${var.project_name}/demo_mode"
  description = "Enable demo mode to bypass trading hours and use demo data"
  type        = "String"
  value       = "false"

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "Demo_Configuration"
    Usage    = "MVP_Demo"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# CloudWatch Log Groups (Free: 5GB data ingestion, 5GB storage)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-ingestion"
  retention_in_days = 7  # Keep short for MVP

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
  })
}

# Lambda function for data ingestion (Free: 1M requests, 400,000 GB-seconds per month)
resource "aws_lambda_function" "data_ingestion" {
  filename         = "../deployment/lambda_ingestion.zip"
  function_name    = "${var.project_name}-ingestion"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_ingestion.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300  # 5 minutes max for free tier

  environment {
    variables = {
      S3_BUCKET_NAME              = aws_s3_bucket.ohlcv_data.id
      FYERS_ACCESS_TOKEN_PARAM    = aws_ssm_parameter.fyers_access_token.name
      FYERS_REFRESH_TOKEN_PARAM   = aws_ssm_parameter.fyers_refresh_token.name
      FYERS_CLIENT_ID_PARAM       = aws_ssm_parameter.fyers_client_id.name
      FYERS_APP_SECRET_PARAM      = aws_ssm_parameter.fyers_app_secret.name
      FYERS_PIN_PARAM             = aws_ssm_parameter.fyers_pin.name
      SNS_TOPIC_ARN               = aws_sns_topic.alerts.arn
      PROJECT_NAME                = var.project_name
      ENVIRONMENT                 = var.environment
      ENABLE_TRADING_HOURS_CHECK  = "true"  # Set to "false" to run 24/7 for testing
    }
  }

  depends_on = [
    null_resource.lambda_dependencies,
    data.archive_file.lambda_zip
  ]

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
  })
}

# Token Generator Lambda Function (AWS-hosted UI backend)
resource "aws_lambda_function" "token_generator" {
  filename         = "../deployment/token_generator.zip"
  function_name    = "${var.project_name}-token-generator"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.token_generator_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30

  environment {
    variables = {
      FYERS_ACCESS_TOKEN_PARAM  = aws_ssm_parameter.fyers_access_token.name
      FYERS_REFRESH_TOKEN_PARAM = aws_ssm_parameter.fyers_refresh_token.name
      FYERS_CLIENT_ID_PARAM     = aws_ssm_parameter.fyers_client_id.name
      FYERS_APP_SECRET_PARAM    = aws_ssm_parameter.fyers_app_secret.name
      PROJECT_NAME              = var.project_name
      CORS_ORIGIN               = "*"  # Allow all origins for simplicity
    }
  }

  depends_on = [
    null_resource.token_generator_dependencies,
    data.archive_file.token_generator_zip
  ]

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "TokenGenerator"
  })
}

# Package Lambda function with dependencies
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "../deployment/lambda_ingestion.zip"
  
  # Just reference the zip file created by null_resource
  source_dir = "../deployment/lambda_package"
  
  depends_on = [null_resource.lambda_dependencies]
}

# Package Token Generator Lambda
data "archive_file" "token_generator_zip" {
  type        = "zip"
  output_path = "../deployment/token_generator.zip"
  
  source_dir = "../deployment/token_generator_package"
  
  depends_on = [null_resource.token_generator_dependencies]
}

# Install dependencies locally and package them
resource "null_resource" "lambda_dependencies" {
  triggers = {
    requirements = filemd5("../ingestion/requirements.txt")
    lambda_code  = filemd5("../ingestion/lambda_ingestion.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      if (Test-Path "../deployment/lambda_package") { Remove-Item "../deployment/lambda_package" -Recurse -Force }
      New-Item -ItemType Directory -Path "../deployment/lambda_package" -Force
      Copy-Item "../ingestion/lambda_ingestion.py" "../deployment/lambda_package/"
      pip install -r "../ingestion/requirements.txt" -t "../deployment/lambda_package" --quiet
      if (Test-Path "../deployment/lambda_ingestion.zip") { Remove-Item "../deployment/lambda_ingestion.zip" -Force }
      Compress-Archive -Path "../deployment/lambda_package/*" -DestinationPath "../deployment/lambda_ingestion.zip"
    EOT
    
    interpreter = ["powershell", "-Command"]
    working_dir = path.module
  }
}

# Package Token Generator dependencies
resource "null_resource" "token_generator_dependencies" {
  triggers = {
    requirements = filemd5("../aws-token-generator/requirements.txt")
    lambda_code  = filemd5("../aws-token-generator/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      if (Test-Path "../deployment/token_generator_package") { Remove-Item "../deployment/token_generator_package" -Recurse -Force }
      New-Item -ItemType Directory -Path "../deployment/token_generator_package" -Force
      Copy-Item "../aws-token-generator/lambda_function.py" "../deployment/token_generator_package/"
      pip install -r "../aws-token-generator/requirements.txt" -t "../deployment/token_generator_package" --quiet
      if (Test-Path "../deployment/token_generator.zip") { Remove-Item "../deployment/token_generator.zip" -Force }
      Compress-Archive -Path "../deployment/token_generator_package/*" -DestinationPath "../deployment/token_generator.zip"
    EOT
    
    interpreter = ["powershell", "-Command"]
    working_dir = path.module
  }
}

# EventBridge rule for scheduled execution (Free: All state changes and scheduled events)
resource "aws_cloudwatch_event_rule" "ingestion_schedule" {
  name                = "${var.project_name}-ingestion-schedule"
  description         = "Trigger data ingestion every 5 minutes during trading hours"
  schedule_expression = "cron(0/5 3-10 ? * MON-FRI *)"  # Every 5 min, 3:00-10:59 AM UTC, Mon-Fri (8:30 AM - 4:29 PM IST)

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ingestion_schedule.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.data_ingestion.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingestion_schedule.arn
}

#===============================================================================
# API GATEWAY FOR TOKEN GENERATOR UI (FREE TIER)
#===============================================================================

# API Gateway for Token Generator
resource "aws_api_gateway_rest_api" "token_generator" {
  name        = "${var.project_name}-token-generator"
  description = "API for Fyers Token Generator Web UI"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    FreeTier = "Yes"
    Purpose  = "TokenGenerator"
  })
}

# CORS configuration for API Gateway
resource "aws_api_gateway_method" "token_generator_options" {
  rest_api_id   = aws_api_gateway_rest_api.token_generator.id
  resource_id   = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "token_generator_options" {
  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  resource_id = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method = aws_api_gateway_method.token_generator_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "token_generator_options" {
  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  resource_id = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method = aws_api_gateway_method.token_generator_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "token_generator_options" {
  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  resource_id = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method = aws_api_gateway_method.token_generator_options.http_method
  status_code = aws_api_gateway_method_response.token_generator_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Main API methods
resource "aws_api_gateway_method" "token_generator_get" {
  rest_api_id   = aws_api_gateway_rest_api.token_generator.id
  resource_id   = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "token_generator_post" {
  rest_api_id   = aws_api_gateway_rest_api.token_generator.id
  resource_id   = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integrations
resource "aws_api_gateway_integration" "token_generator_get" {
  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  resource_id = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method = aws_api_gateway_method.token_generator_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.token_generator.invoke_arn
}

resource "aws_api_gateway_integration" "token_generator_post" {
  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  resource_id = aws_api_gateway_rest_api.token_generator.root_resource_id
  http_method = aws_api_gateway_method.token_generator_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.token_generator.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "token_generator_api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.token_generator.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "token_generator" {
  depends_on = [
    aws_api_gateway_integration.token_generator_get,
    aws_api_gateway_integration.token_generator_post,
    aws_api_gateway_integration.token_generator_options
  ]

  rest_api_id = aws_api_gateway_rest_api.token_generator.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Lambda (Free)
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-lambda-permissions"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ohlcv_data.arn,
          "${aws_s3_bucket.ohlcv_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = [
          aws_ssm_parameter.fyers_access_token.arn,
          aws_ssm_parameter.fyers_refresh_token.arn,
          aws_ssm_parameter.fyers_client_id.arn,
          aws_ssm_parameter.fyers_app_secret.arn,
          aws_ssm_parameter.fyers_pin.arn,
          aws_ssm_parameter.demo_mode.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

#===============================================================================
# COMMENTED OUT SERVICES - EXPENSIVE/NOT FREE TIER
# Uncomment these when ready to scale beyond MVP
#===============================================================================

/*
# RDS PostgreSQL - NOT FREE TIER ($15-20/month minimum)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
  })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  allocated_storage     = 20
  storage_type          = "gp3"
  storage_encrypted     = true
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"
  
  db_name  = "stockdata"
  username = "stockuser"
  password = random_password.rds_password.result
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  backup_retention_period = 3
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-postgres"
    Service = "RDS"
    Cost = "HIGH"
  })
}

resource "random_password" "rds_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project_name}-rds-credentials"
  description             = "RDS PostgreSQL credentials"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = aws_db_instance.postgres.db_name
    username = aws_db_instance.postgres.username
    password = aws_db_instance.postgres.password
  })
}
*/

/*
# ECS Fargate - NOT FREE TIER ($20-50/month minimum)
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Service = "ECS"
    Cost = "HIGH"
  })
}

resource "aws_ecs_task_definition" "ingestion" {
  family                   = "${var.project_name}-ingestion"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "ingestion"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${aws_ecr_repository.ingestion.name}:latest"
      
      essential = true
      
      environment = [
        {
          name  = "S3_BUCKET_NAME"
          value = aws_s3_bucket.ohlcv_data.id
        },
        {
          name  = "FYERS_SECRET_NAME"
          value = aws_secretsmanager_secret.fyers_credentials.name
        },
        {
          name  = "SNS_TOPIC_ARN"
          value = aws_sns_topic.alerts.arn
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_ingestion.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Service = "ECS"
    Cost = "HIGH"
  })
}

resource "aws_ecr_repository" "ingestion" {
  name                 = "${var.project_name}-ingestion"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Service = "ECR"
    Cost = "MEDIUM"
  })
}

resource "aws_cloudwatch_log_group" "ecs_ingestion" {
  name              = "/ecs/${var.project_name}-ingestion"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Service = "ECS"
    Cost = "MEDIUM"
  })
}
*/

/*
# AWS Glue - NOT FREE TIER ($0.44/DPU-hour, minimum $5-10/month)
resource "aws_glue_catalog_database" "ohlcv" {
  name        = "${var.project_name}_ohlcv"
  description = "OHLCV stock data catalog"

  tags = merge(local.common_tags, {
    Service = "Glue"
    Cost = "HIGH"
  })
}

resource "aws_glue_job" "etl" {
  name         = "${var.project_name}-etl"
  role_arn     = aws_iam_role.glue.arn
  glue_version = "4.0"

  worker_type       = "G.1X"
  number_of_workers = 3
  
  execution_class = "FLEX"

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.id}/etl/glue_job.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--source_bucket"                    = aws_s3_bucket.ohlcv_data.id
    "--target_bucket"                    = aws_s3_bucket.ohlcv_data.id
    "--database_name"                    = aws_glue_catalog_database.ohlcv.name
    "--sns_topic_arn"                    = aws_sns_topic.alerts.arn
  }

  execution_property {
    max_concurrent_runs = 2
  }

  max_retries = 2
  timeout     = 60

  tags = merge(local.common_tags, {
    Service = "Glue"
    Cost = "HIGH"
  })
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${local.bucket_name}-scripts"

  tags = merge(local.common_tags, {
    Name = "Glue Scripts Bucket"
    Service = "Glue"
    Cost = "LOW"
  })
}
*/

/*
# Athena - Free tier has limitations, paid after 10TB scanned
resource "aws_athena_workgroup" "ohlcv" {
  name = "${var.project_name}-ohlcv"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics         = true
    bytes_scanned_cutoff_per_query     = 100000000  # 100 MB limit for MVP
    result_configuration_updates       = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Service = "Athena"
    Cost = "MEDIUM"
  })
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.bucket_name}-athena-results"

  tags = merge(local.common_tags, {
    Name = "Athena Query Results"
    Service = "Athena"
    Cost = "LOW"
  })
}
*/

# Cost monitoring budget for MVP
resource "aws_budgets_budget" "mvp_budget" {
  name         = "${var.project_name}-mvp-budget"
  budget_type  = "COST"
  limit_amount = "5"  # $5 monthly limit for MVP
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = "2025-01-01_00:00"
  
  cost_filter {
    name   = "Service"
    values = [
      "Amazon Simple Storage Service",
      "AWS Lambda",
      "Amazon Simple Notification Service",
      "AWS Systems Manager"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 50   # Alert at 50% of budget ($2.50)
    threshold_type            = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80   # Alert at 80% of budget ($4.00)
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }

  tags = merge(local.common_tags, {
    Purpose = "CostControl"
    Budget = "MVP"
  })
}

#===============================================================================
# OUTPUTS - MVP VERSION
#===============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for OHLCV data"
  value       = aws_s3_bucket.ohlcv_data.id
}

output "lambda_function_name" {
  description = "Lambda function name for data ingestion"
  value       = aws_lambda_function.data_ingestion.function_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "fyers_parameter_prefix" {
  description = "Fyers API credentials SSM parameter prefix"
  value       = "/${var.project_name}/fyers/"
}

output "fyers_access_token_param" {
  description = "Fyers access token SSM parameter name"
  value       = aws_ssm_parameter.fyers_access_token.name
}

output "fyers_refresh_token_param" {
  description = "Fyers refresh token SSM parameter name"
  value       = aws_ssm_parameter.fyers_refresh_token.name
}

output "fyers_client_id_param" {
  description = "Fyers client ID SSM parameter name"
  value       = aws_ssm_parameter.fyers_client_id.name
}

output "fyers_app_secret_param" {
  description = "Fyers app secret SSM parameter name"
  value       = aws_ssm_parameter.fyers_app_secret.name
}

output "fyers_pin_param" {
  description = "Fyers PIN SSM parameter name (optional)"
  value       = aws_ssm_parameter.fyers_pin.name
}

output "mvp_budget_name" {
  description = "MVP cost budget name"
  value       = aws_budgets_budget.mvp_budget.name
}

output "cloudwatch_logs_url" {
  description = "CloudWatch logs URL for monitoring Lambda function"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
}

output "s3_console_url" {
  description = "S3 console URL for viewing stored data"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.ohlcv_data.id}?region=${data.aws_region.current.name}"
}

output "token_generator_url" {
  description = "AWS-hosted Token Generator Web UI URL"
  value       = "https://${aws_api_gateway_rest_api.token_generator.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod"
}

output "token_generator_api_id" {
  description = "API Gateway ID for token generator"
  value       = aws_api_gateway_rest_api.token_generator.id
}

# MVP Deployment Instructions
output "mvp_deployment_instructions" {
  description = "Instructions for deploying the MVP"
  value = <<-EOT
    MVP Deployment Instructions:
    
    1. This configuration uses only AWS Free Tier services:
       - S3 (5GB storage, 20K GET, 2K PUT requests/month)
       - Lambda (1M requests, 400K GB-seconds/month)
       - SNS (1K notifications/month)
       - CloudWatch Logs (5GB ingestion, 5GB storage/month)
       - SSM Parameter Store (Free for standard parameters)
    
    2. Estimated monthly cost: $0.00 - $1.00 (completely free tier compliant)
    
    3. To deploy:
       terraform init
       terraform plan -var="notification_email=your-email@example.com"
       terraform apply -var="notification_email=your-email@example.com"
    
    4. After deployment, use the AWS-hosted Token Generator UI:
       - Open: https://{api-gateway-id}.execute-api.ap-south-1.amazonaws.com/prod
       - Generate tokens daily using the web interface (no local scripts needed!)
       - Tokens are automatically stored in SSM parameters
    
    5. Manual SSM parameter updates (if needed):
       aws ssm put-parameter --name "/{project-name}/fyers/refresh_token" --value "your-refresh-token" --type "SecureString" --overwrite
       aws ssm put-parameter --name "/{project-name}/fyers/client_id" --value "your-client-id" --type "SecureString" --overwrite
    
    5. To scale up later, uncomment the expensive services in this file:
       - RDS PostgreSQL (for structured data storage)
       - ECS Fargate (for containerized processing)
       - AWS Glue (for ETL processing)
       - Athena (for analytics)
    
    5. Monitor costs in AWS Billing Dashboard and set up budget alerts.
  EOT
}
