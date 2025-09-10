# Environment Setup Helper (PowerShell)
# Creates and configures your .env file for the Stock Price Feed Parser

param(
    [switch]$PostDeployment,
    [switch]$Validate
)

function Write-Header($text) {
    Write-Host "`n$('='*60)" -ForegroundColor Blue
    Write-Host "  $text" -ForegroundColor Blue
    Write-Host "$('='*60)" -ForegroundColor Blue
}

function Write-Success($text) {
    Write-Host "✅ $text" -ForegroundColor Green
}

function Write-Warning($text) {
    Write-Host "⚠️  $text" -ForegroundColor Yellow
}

function Write-Error($text) {
    Write-Host "❌ $text" -ForegroundColor Red
}

function Get-AwsInfo {
    try {
        $identity = aws sts get-caller-identity | ConvertFrom-Json
        $region = aws configure get region
        if (-not $region) { $region = "ap-south-1" }
        
        return @{
            AccountId = $identity.Account
            Region = $region
        }
    }
    catch {
        Write-Warning "Could not get AWS info: $($_.Exception.Message)"
        return @{
            AccountId = ""
            Region = "ap-south-1"
        }
    }
}

function New-EnvFile {
    $templateFile = ".env.example"
    $envFile = ".env"
    
    if (-not (Test-Path $templateFile)) {
        Write-Error "Template file $templateFile not found!"
        return $false
    }
    
    if (Test-Path $envFile) {
        $response = Read-Host "`n$envFile already exists. Overwrite? (y/n)"
        if ($response -ne 'y') {
            Write-Host "Keeping existing .env file."
            return $true
        }
    }
    
    Copy-Item $templateFile $envFile
    Write-Success "Created $envFile from template"
    return $true
}

function Update-EnvFile($config) {
    $envFile = ".env"
    
    if (-not (Test-Path $envFile)) {
        Write-Error "$envFile not found!"
        return $false
    }
    
    $content = Get-Content $envFile -Raw
    
    # Update values
    $replacements = @{
        'NOTIFICATION_EMAIL=your-email@example.com' = "NOTIFICATION_EMAIL=$($config.Email)"
        'AWS_DEFAULT_REGION=ap-south-1' = "AWS_DEFAULT_REGION=$($config.Region)"
        'PROJECT_NAME=stock-pipeline-mvp' = "PROJECT_NAME=$($config.Project)"
        'ENVIRONMENT=dev' = "ENVIRONMENT=$($config.Environment)"
        'MONTHLY_BUDGET_LIMIT=5' = "MONTHLY_BUDGET_LIMIT=$($config.Budget)"
    }
    
    foreach ($replacement in $replacements.GetEnumerator()) {
        $content = $content -replace [regex]::Escape($replacement.Key), $replacement.Value
    }
    
    Set-Content -Path $envFile -Value $content
    Write-Success "Updated .env file with your configuration"
    return $true
}

function Get-UserConfig {
    Write-Header "Environment Configuration"
    
    $config = @{}
    
    # Email address
    do {
        $email = Read-Host "Enter your email address for notifications"
        if ($email -match '^[^@]+@[^@]+\.[^@]+$') {
            $config.Email = $email
            break
        }
        else {
            Write-Error "Invalid email format. Please try again."
        }
    } while ($true)
    
    # AWS region
    $awsInfo = Get-AwsInfo
    $defaultRegion = $awsInfo.Region
    $region = Read-Host "Enter AWS region [$defaultRegion]"
    $config.Region = if ($region) { $region } else { $defaultRegion }
    
    # Project name
    $project = Read-Host "Enter project name [stock-pipeline-mvp]"
    $config.Project = if ($project) { $project } else { "stock-pipeline-mvp" }
    
    # Environment
    $environment = Read-Host "Enter environment [dev]"
    $config.Environment = if ($environment) { $environment } else { "dev" }
    
    # Budget limit
    $budget = Read-Host "Enter monthly budget limit in USD [5]"
    $config.Budget = if ($budget) { $budget } else { "5" }
    
    return $config
}

function Update-EnvAfterDeployment {
    Write-Header "Post-Deployment Environment Update"
    
    $envFile = ".env"
    if (-not (Test-Path $envFile)) {
        Write-Error "$envFile not found!"
        return $false
    }
    
    Write-Host "After successful deployment, you need to update your .env file with the actual AWS resource names."
    Write-Host "You can find these in the deployment output or AWS Console."
    Write-Host ""
    
    # Get resource names from user
    $resources = @{}
    
    $bucketName = Read-Host "Enter S3 bucket name (from deployment output)"
    if ($bucketName) { $resources['S3_BUCKET_NAME'] = $bucketName }
    
    $snsTopicArn = Read-Host "Enter SNS topic ARN (from deployment output)"
    if ($snsTopicArn) { $resources['SNS_TOPIC_ARN'] = $snsTopicArn }
    
    $secretName = Read-Host "Enter Fyers secret name (from deployment output)"
    if ($secretName) { $resources['FYERS_SECRET_NAME'] = $secretName }
    
    $lambdaName = Read-Host "Enter Lambda function name (from deployment output)"
    if ($lambdaName) { $resources['LAMBDA_FUNCTION_NAME'] = $lambdaName }
    
    if ($resources.Count -eq 0) {
        Write-Host "No resources to update."
        return $true
    }
    
    # Update .env file
    $content = Get-Content $envFile -Raw
    
    foreach ($resource in $resources.GetEnumerator()) {
        $oldLine = "$($resource.Key)="
        $newLine = "$($resource.Key)=$($resource.Value)"
        $content = $content -replace [regex]::Escape($oldLine), $newLine
    }
    
    Set-Content -Path $envFile -Value $content
    Write-Success "Updated .env file with AWS resource names"
    return $true
}

function Test-EnvFile {
    Write-Header "Validating Environment Configuration"
    
    $envFile = ".env"
    if (-not (Test-Path $envFile)) {
        Write-Error "$envFile not found!"
        return $false
    }
    
    $requiredVars = @(
        'NOTIFICATION_EMAIL',
        'AWS_DEFAULT_REGION',
        'PROJECT_NAME',
        'ENVIRONMENT'
    )
    
    $optionalVars = @(
        'S3_BUCKET_NAME',
        'SNS_TOPIC_ARN',
        'FYERS_SECRET_NAME',
        'LAMBDA_FUNCTION_NAME'
    )
    
    $content = Get-Content $envFile -Raw
    $missingRequired = @()
    $emptyOptional = @()
    
    foreach ($var in $requiredVars) {
        if ($content -notmatch "$var=" -or $content -match "$var=your-" -or $content -match "$var= ") {
            $missingRequired += $var
        }
        else {
            Write-Success "$var is configured"
        }
    }
    
    foreach ($var in $optionalVars) {
        if ($content -match "$var=") {
            $lines = $content -split "`n"
            $configured = $false
            foreach ($line in $lines) {
                if ($line.StartsWith("$var=") -and -not $line.Trim().EndsWith('=')) {
                    Write-Success "$var is configured"
                    $configured = $true
                    break
                }
            }
            if (-not $configured) {
                $emptyOptional += $var
            }
        }
    }
    
    if ($missingRequired.Count -gt 0) {
        Write-Error "Missing required variables: $($missingRequired -join ', ')"
        return $false
    }
    
    if ($emptyOptional.Count -gt 0) {
        Write-Warning "Empty optional variables (fill after deployment): $($emptyOptional -join ', ')"
    }
    
    Write-Success "Environment configuration is valid!"
    return $true
}

function Show-NextSteps {
    Write-Header "Next Steps"
    
    Write-Host "🚀 Your environment is configured! Here's what to do next:" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Deploy the infrastructure:" -ForegroundColor Cyan
    Write-Host "   cd deployment"
    Write-Host "   .\deploy-mvp.ps1 -NotificationEmail `"$(Get-Content .env | Where-Object { $_ -match 'NOTIFICATION_EMAIL=' } | ForEach-Object { $_.Split('=')[1] })`""
    Write-Host ""
    Write-Host "2. After deployment, update .env with resource names:" -ForegroundColor Cyan
    Write-Host "   .\scripts\env_setup.ps1 -PostDeployment"
    Write-Host ""
    Write-Host "3. Configure Fyers API credentials in AWS Secrets Manager" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. Test your setup:" -ForegroundColor Cyan
    Write-Host "   .\scripts\pre_deployment_check.ps1"
    Write-Host ""
    Write-Host "5. Start analyzing data:" -ForegroundColor Cyan
    Write-Host "   python analysis\mvp_analyzer.py"
}

function Main {
    Write-Host "🔧 Stock Price Feed Parser - Environment Setup" -ForegroundColor Blue
    Write-Host "=" * 50
    
    if ($PostDeployment) {
        Update-EnvAfterDeployment
        return
    }
    
    if ($Validate) {
        Test-EnvFile
        return
    }
    
    # Main setup flow
    Write-Host "`nThis tool will help you create and configure your .env file."
    Write-Host "The .env file contains all configuration settings for your pipeline."
    
    # Create .env file from template
    if (-not (New-EnvFile)) {
        return
    }
    
    # Get user configuration
    $config = Get-UserConfig
    
    # Update .env file
    if (-not (Update-EnvFile $config)) {
        return
    }
    
    # Validate configuration
    if (-not (Test-EnvFile)) {
        return
    }
    
    Write-Success "Environment setup complete!"
    Show-NextSteps
}

# Script entry point
try {
    Main
}
catch {
    Write-Host "`n`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
