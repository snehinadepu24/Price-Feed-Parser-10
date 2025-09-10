# Manual Token Generation - PowerShell Script
# For Windows users who prefer PowerShell over Python

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3", "refresh")]
    [string]$Step,
    
    [Parameter(Mandatory = $false)]
    [string]$AuthCode,
    
    [Parameter(Mandatory = $false)]
    [string]$AccessToken,
    
    [Parameter(Mandatory = $false)]
    [string]$RefreshToken,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $false)]
    [string]$AppSecret
)

# Configuration
$FYERS_BASE_URL = "https://api-t2.fyers.in"
$REDIRECT_URI = "https://trade.fyers.in/api-login/redirect-to-app"
$PROJECT_PREFIX = "stock-pipeline-mvp"

function Get-AppHash {
    param([string]$ClientId, [string]$AppSecret)
    
    $inputString = "${ClientId}:${AppSecret}"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputString)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
    return $hash.ToLower()
}

function Get-FyersConfig {
    Write-Host "🔐 Fyers Configuration" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # Try environment variables first
    $config = @{}
    $config.ClientId = $env:FYERS_CLIENT_ID
    $config.AppSecret = $env:FYERS_APP_SECRET
    $config.AwsProfile = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "default" }
    $config.AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-south-1" }
    
    # Prompt for missing values
    if (-not $config.ClientId -and -not $ClientId) {
        $config.ClientId = Read-Host "Enter your Fyers Client ID"
    }
    elseif ($ClientId) {
        $config.ClientId = $ClientId
    }
    
    if (-not $config.AppSecret -and -not $AppSecret) {
        $config.AppSecret = Read-Host "Enter your Fyers App Secret"
    }
    elseif ($AppSecret) {
        $config.AppSecret = $AppSecret
    }
    
    if (-not $config.ClientId -or -not $config.AppSecret) {
        Write-Host "❌ Error: Client ID and App Secret are required!" -ForegroundColor Red
        exit 1
    }
    
    return $config
}

function Invoke-Step1GenerateAuthUrl {
    param($Config)
    
    Write-Host "🚀 Step 1: Generate Authorization URL" -ForegroundColor Green
    Write-Host "=" * 50
    
    # Build authorization URL
    $params = @{
        'client_id'     = $Config.ClientId
        'redirect_uri'  = $REDIRECT_URI
        'response_type' = 'code'
        'state'         = 'sample_state'
    }
    
    $queryString = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    $authUrl = "$FYERS_BASE_URL/api/v3/generate-authcode?$queryString"
    
    Write-Host "📋 Your Authorization URL:" -ForegroundColor Yellow
    Write-Host "🔗 $authUrl" -ForegroundColor Blue
    Write-Host ""
    Write-Host "📖 Instructions:" -ForegroundColor Yellow
    Write-Host "1. Click the URL above (or copy-paste it in your browser)"
    Write-Host "2. Login to your Fyers account"
    Write-Host "3. After successful login, you'll be redirected to a URL"
    Write-Host "4. Copy the 'auth_code' parameter from the redirect URL"
    Write-Host "5. Run: .\manual_token_generator.ps1 -Step 2 -AuthCode YOUR_AUTH_CODE"
    Write-Host ""
    
    # Optional: Auto-open in browser
    $openBrowser = Read-Host "🌐 Open URL in browser automatically? (y/n)"
    if ($openBrowser -eq 'y' -or $openBrowser -eq 'yes') {
        Start-Process $authUrl
        Write-Host "✅ URL opened in browser" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "🔄 Next Step: Run with -Step 2 and your auth code" -ForegroundColor Cyan
}

function Invoke-Step2GetTokens {
    param($Config, $AuthCode)
    
    Write-Host "🔑 Step 2: Generate Access & Refresh Tokens" -ForegroundColor Green
    Write-Host "=" * 50
    
    # Generate app hash
    $appHash = Get-AppHash -ClientId $Config.ClientId -AppSecret $Config.AppSecret
    
    # Token request payload
    $tokenPayload = @{
        'grant_type' = 'authorization_code'
        'appIdHash'  = $appHash
        'code'       = $AuthCode
    } | ConvertTo-Json
    
    # Make token request
    $tokenUrl = "$FYERS_BASE_URL/api/v3/validate-authcode"
    $headers = @{
        'Content-Type' = 'application/json'
    }
    
    Write-Host "📡 Making token request to: $tokenUrl" -ForegroundColor Blue
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenPayload -Headers $headers -TimeoutSec 30
        
        Write-Host "📄 Response: $($response | ConvertTo-Json -Depth 3)" -ForegroundColor Gray
        
        if ($response.s -eq 'ok') {
            $accessToken = $response.access_token
            $refreshToken = $response.refresh_token
            
            if ($accessToken -and $refreshToken) {
                Write-Host "✅ Tokens generated successfully!" -ForegroundColor Green
                Write-Host "🔐 Access Token: $($accessToken.Substring(0, 20))...$($accessToken.Substring($accessToken.Length - 10))" -ForegroundColor Yellow
                Write-Host "🔄 Refresh Token: $($refreshToken.Substring(0, 20))...$($refreshToken.Substring($refreshToken.Length - 10))" -ForegroundColor Yellow
                
                # Save to local file
                $tokenData = @{
                    'access_token'  = $accessToken
                    'refresh_token' = $refreshToken
                    'generated_at'  = (Get-Date).ToString('o')
                    'client_id'     = $Config.ClientId
                }
                
                $tokenData | ConvertTo-Json -Depth 3 | Out-File -FilePath "fyers_tokens.json" -Encoding UTF8
                
                Write-Host "💾 Tokens saved to: fyers_tokens.json" -ForegroundColor Green
                Write-Host ""
                Write-Host "🔄 Next Step: Run with -Step 3 to update AWS SSM" -ForegroundColor Cyan
                Write-Host "Command: .\manual_token_generator.ps1 -Step 3 -AccessToken '$accessToken' -RefreshToken '$refreshToken'" -ForegroundColor Blue
                
                return $accessToken, $refreshToken
            }
            else {
                Write-Host "❌ Error: Tokens not found in response" -ForegroundColor Red
            }
        }
        else {
            Write-Host "❌ Error: $($response.message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    return $null, $null
}

function Invoke-Step3UpdateSSM {
    param($Config, $AccessToken, $RefreshToken)
    
    Write-Host "☁️ Step 3: Update AWS SSM Parameters" -ForegroundColor Green
    Write-Host "=" * 50
    
    try {
        # SSM parameter names
        $accessTokenParam = "/$PROJECT_PREFIX/fyers/access_token"
        $refreshTokenParam = "/$PROJECT_PREFIX/fyers/refresh_token"
        $clientIdParam = "/$PROJECT_PREFIX/fyers/client_id"
        
        Write-Host "📡 Updating SSM parameters in region: $($Config.AwsRegion)" -ForegroundColor Blue
        Write-Host "🏷️ Parameter prefix: /$PROJECT_PREFIX/fyers/" -ForegroundColor Blue
        
        # Update access token
        Write-Host "🔐 Updating access token: $accessTokenParam" -ForegroundColor Yellow
        aws ssm put-parameter --name $accessTokenParam --value $AccessToken --type "SecureString" --overwrite --description "Fyers access token - updated $(Get-Date -Format 'o')" --profile $Config.AwsProfile --region $Config.AwsRegion
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Access token updated" -ForegroundColor Green
        }
        else {
            throw "Failed to update access token"
        }
        
        # Update refresh token
        Write-Host "🔄 Updating refresh token: $refreshTokenParam" -ForegroundColor Yellow
        aws ssm put-parameter --name $refreshTokenParam --value $RefreshToken --type "SecureString" --overwrite --description "Fyers refresh token - updated $(Get-Date -Format 'o')" --profile $Config.AwsProfile --region $Config.AwsRegion
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Refresh token updated" -ForegroundColor Green
        }
        else {
            throw "Failed to update refresh token"
        }
        
        # Update client ID
        Write-Host "🆔 Updating client ID: $clientIdParam" -ForegroundColor Yellow
        aws ssm put-parameter --name $clientIdParam --value $Config.ClientId --type "SecureString" --overwrite --description "Fyers client ID - updated $(Get-Date -Format 'o')" --profile $Config.AwsProfile --region $Config.AwsRegion
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Client ID updated" -ForegroundColor Green
        }
        else {
            throw "Failed to update client ID"
        }
        
        Write-Host ""
        Write-Host "🎉 All SSM parameters updated successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🧪 Testing token validity..." -ForegroundColor Yellow
        
        # Test the tokens
        $testSuccess = Test-TokenValidity -ClientId $Config.ClientId -AccessToken $AccessToken
        
        if ($testSuccess) {
            Write-Host "✅ Token validation successful!" -ForegroundColor Green
            Write-Host "🚀 Your system is ready to run automatically!" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Token validation failed - please check the tokens" -ForegroundColor Yellow
        }
        
    }
    catch {
        Write-Host "❌ Error updating SSM: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 Make sure you have:" -ForegroundColor Yellow
        Write-Host "   - AWS CLI installed and configured" 
        Write-Host "   - Correct AWS credentials"
        Write-Host "   - SSM permissions"
        Write-Host "   - Correct region selected"
    }
}

function Test-TokenValidity {
    param($ClientId, $AccessToken)
    
    try {
        $testUrl = "https://api-t1.fyers.in/api/v3/profile"
        $headers = @{
            'Authorization' = "${ClientId}:${AccessToken}"
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Headers $headers -TimeoutSec 10
        
        if ($response.s -eq 'ok') {
            Write-Host "📊 Profile: $($response.data.name)" -ForegroundColor Blue
            return $true
        }
        
        Write-Host "🔍 Test response: $($response | ConvertTo-Json)" -ForegroundColor Gray
        return $false
    }
    catch {
        Write-Host "⚠️ Token test failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Invoke-RefreshExistingToken {
    param($Config)
    
    Write-Host "🔄 Refresh Existing Token" -ForegroundColor Green
    Write-Host "=" * 50
    
    # Try to get refresh token from SSM first
    try {
        $refreshTokenParam = "/$PROJECT_PREFIX/fyers/refresh_token"
        $response = aws ssm get-parameter --name $refreshTokenParam --with-decryption --profile $Config.AwsProfile --region $Config.AwsRegion --output json | ConvertFrom-Json
        $refreshToken = $response.Parameter.Value
        
        Write-Host "✅ Found refresh token in SSM" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Could not get refresh token from SSM: $($_.Exception.Message)" -ForegroundColor Yellow
        $refreshToken = Read-Host "Enter your refresh token manually"
    }
    
    if (-not $refreshToken -or $refreshToken -eq 'CHANGE_ME') {
        Write-Host "❌ No valid refresh token available" -ForegroundColor Red
        return
    }
    
    # Generate app hash
    $appHash = Get-AppHash -ClientId $Config.ClientId -AppSecret $Config.AppSecret
    
    # Refresh token request
    $refreshPayload = @{
        'grant_type'    = 'refresh_token'
        'appIdHash'     = $appHash
        'refresh_token' = $refreshToken
    } | ConvertTo-Json
    
    $refreshUrl = "$FYERS_BASE_URL/api/v3/validate-refresh-token"
    $headers = @{
        'Content-Type' = 'application/json'
    }
    
    Write-Host "📡 Refreshing token..." -ForegroundColor Blue
    
    try {
        $response = Invoke-RestMethod -Uri $refreshUrl -Method Post -Body $refreshPayload -Headers $headers -TimeoutSec 30
        
        if ($response.s -eq 'ok' -and $response.access_token) {
            $newAccessToken = $response.access_token
            Write-Host "✅ Token refreshed successfully!" -ForegroundColor Green
            Write-Host "🔐 New Access Token: $($newAccessToken.Substring(0, 20))...$($newAccessToken.Substring($newAccessToken.Length - 10))" -ForegroundColor Yellow
            
            # Update SSM with new access token
            try {
                $accessTokenParam = "/$PROJECT_PREFIX/fyers/access_token"
                aws ssm put-parameter --name $accessTokenParam --value $newAccessToken --type "SecureString" --overwrite --description "Fyers access token - refreshed $(Get-Date -Format 'o')" --profile $Config.AwsProfile --region $Config.AwsRegion
                
                Write-Host "✅ SSM parameter updated with new access token" -ForegroundColor Green
                
                # Test the new token
                if (Test-TokenValidity -ClientId $Config.ClientId -AccessToken $newAccessToken) {
                    Write-Host "🎉 Token refresh and validation successful!" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "⚠️ Could not update SSM: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "💾 New access token: $newAccessToken" -ForegroundColor Blue
            }
        }
        else {
            Write-Host "❌ Refresh failed: $($response.message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
Add-Type -AssemblyName System.Web

Write-Host "🔐 Manual Fyers Token Generator (PowerShell)" -ForegroundColor Cyan
Write-Host "=" * 50
Write-Host "⏰ Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Load configuration
$config = Get-FyersConfig

# Execute based on step
switch ($Step) {
    "1" { 
        Invoke-Step1GenerateAuthUrl -Config $config 
    }
    "2" { 
        if (-not $AuthCode) {
            Write-Host "❌ Error: -AuthCode is required for step 2" -ForegroundColor Red
            exit 1
        }
        Invoke-Step2GetTokens -Config $config -AuthCode $AuthCode 
    }
    "3" { 
        if (-not $AccessToken -or -not $RefreshToken) {
            Write-Host "❌ Error: -AccessToken and -RefreshToken are required for step 3" -ForegroundColor Red
            exit 1
        }
        Invoke-Step3UpdateSSM -Config $config -AccessToken $AccessToken -RefreshToken $RefreshToken 
    }
    "refresh" { 
        Invoke-RefreshExistingToken -Config $config 
    }
    default {
        Write-Host "❓ No step specified. Here's what you can do:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "🚀 Full token generation process:" -ForegroundColor Green
        Write-Host "   1. Generate auth URL:     .\manual_token_generator.ps1 -Step 1"
        Write-Host "   2. Get tokens:           .\manual_token_generator.ps1 -Step 2 -AuthCode CODE"
        Write-Host "   3. Update SSM:           .\manual_token_generator.ps1 -Step 3 -AccessToken TOKEN -RefreshToken TOKEN"
        Write-Host ""
        Write-Host "🔄 Quick refresh:" -ForegroundColor Blue
        Write-Host "   Refresh existing:        .\manual_token_generator.ps1 -Step refresh"
        Write-Host ""
        Write-Host "💡 Example with inline credentials:" -ForegroundColor Yellow
        Write-Host "   .\manual_token_generator.ps1 -Step 1 -ClientId 'YOUR_ID' -AppSecret 'YOUR_SECRET'"
    }
}
