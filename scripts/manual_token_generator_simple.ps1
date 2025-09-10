# Fyers API Manual Token Generator - Simple Version
# Script to manually generate and update Fyers API tokens

# Set Error Action
$ErrorActionPreference = "Stop"

# Load Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"

Write-Host "===== Fyers API Manual Token Generator =====" -ForegroundColor Cyan
Write-Host ""

# Check if config file exists
if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
    $ClientId = $Config.client_id
    $AppSecret = $Config.app_secret
    $RedirectUri = $Config.redirect_uri
    Write-Host "Configuration loaded from config.json" -ForegroundColor Green
} else {
    Write-Host "Config file not found. Please enter your credentials:" -ForegroundColor Yellow
    $ClientId = Read-Host "Enter Client ID"
    $AppSecret = Read-Host "Enter App Secret"
    $RedirectUri = Read-Host "Enter Redirect URI (default: https://127.0.0.1:3000/)"
    
    if ([string]::IsNullOrEmpty($RedirectUri)) {
        $RedirectUri = "https://127.0.0.1:3000/"
    }
}

Write-Host ""
Write-Host "Available Commands:" -ForegroundColor Yellow
Write-Host "1. step1    - Generate authorization URL"
Write-Host "2. step2    - Exchange auth code for tokens"
Write-Host "3. step3    - Update SSM parameters"
Write-Host "4. refresh  - Refresh access token using refresh token"
Write-Host "5. exit     - Exit the script"
Write-Host ""

while ($true) {
    $Command = Read-Host "Enter command (step1/step2/step3/refresh/exit)"
    
    switch ($Command.ToLower()) {
        "step1" {
            try {
                # Generate app hash
                $AppHashInput = "${ClientId}:${AppSecret}"
                $SHA256 = [System.Security.Cryptography.SHA256]::Create()
                $HashBytes = $SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($AppHashInput))
                $AppHash = [System.BitConverter]::ToString($HashBytes).Replace("-", "").ToLower()
                
                # Create authorization URL
                Add-Type -AssemblyName System.Web
                $EncodedRedirectUri = [System.Web.HttpUtility]::UrlEncode($RedirectUri)
                $AuthUrl = "https://api.fyers.in/api/v2/generate-authcode?client_id=${ClientId}&redirect_uri=${EncodedRedirectUri}&response_type=code&state=sample&scope=openid"
                
                Write-Host ""
                Write-Host "Step 1: Authorization URL Generated" -ForegroundColor Green
                Write-Host "App Hash: $AppHash" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Authorization URL:" -ForegroundColor Yellow
                Write-Host $AuthUrl
                Write-Host ""
                Write-Host "1. Open this URL in your browser"
                Write-Host "2. Login to Fyers and authorize the app"
                Write-Host "3. Copy the 'auth_code' from the redirected URL"
                Write-Host "4. Run 'step2' with the auth_code"
                Write-Host ""
                
                # Store app hash for next step
                $global:AppHash = $AppHash
            }
            catch {
                Write-Host "Error in Step 1: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        "step2" {
            try {
                if (-not $global:AppHash) {
                    Write-Host "Please run 'step1' first to generate app hash" -ForegroundColor Red
                    continue
                }
                
                $AuthCode = Read-Host "Enter the auth_code from the redirected URL"
                
                if ([string]::IsNullOrEmpty($AuthCode)) {
                    Write-Host "Auth code cannot be empty" -ForegroundColor Red
                    continue
                }
                
                # Prepare token request
                $TokenUrl = "https://api.fyers.in/api/v2/token"
                $Body = @{
                    grant_type = "authorization_code"
                    appIdHash = $global:AppHash
                    code = $AuthCode
                } | ConvertTo-Json
                
                $Headers = @{
                    "Content-Type" = "application/json"
                }
                
                Write-Host "Exchanging auth code for tokens..." -ForegroundColor Yellow
                
                $Response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $Body -Headers $Headers
                
                if ($Response.s -eq "ok") {
                    $AccessToken = $Response.access_token
                    $RefreshToken = $Response.refresh_token
                    
                    Write-Host ""
                    Write-Host "Step 2: Tokens Generated Successfully!" -ForegroundColor Green
                    Write-Host "Access Token: $AccessToken" -ForegroundColor Cyan
                    Write-Host "Refresh Token: $RefreshToken" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Run 'step3' to update SSM parameters"
                    Write-Host ""
                    
                    # Store tokens for next step
                    $global:AccessToken = $AccessToken
                    $global:RefreshToken = $RefreshToken
                } else {
                    Write-Host "Token exchange failed: $($Response.message)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "Error in Step 2: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        "step3" {
            try {
                if (-not $global:AccessToken -or -not $global:RefreshToken) {
                    Write-Host "Please run 'step2' first to generate tokens" -ForegroundColor Red
                    continue
                }
                
                Write-Host "Updating SSM parameters..." -ForegroundColor Yellow
                
                # Update access token
                $AccessTokenCmd = "aws ssm put-parameter --name '/fyers-api/access-token' --value '$($global:AccessToken)' --type SecureString --overwrite --region ap-south-1"
                $AccessResult = Invoke-Expression $AccessTokenCmd
                
                # Update refresh token
                $RefreshTokenCmd = "aws ssm put-parameter --name '/fyers-api/refresh-token' --value '$($global:RefreshToken)' --type SecureString --overwrite --region ap-south-1"
                $RefreshResult = Invoke-Expression $RefreshTokenCmd
                
                Write-Host ""
                Write-Host "Step 3: SSM Parameters Updated Successfully!" -ForegroundColor Green
                Write-Host "✓ Access token updated in SSM"
                Write-Host "✓ Refresh token updated in SSM"
                Write-Host ""
                Write-Host "Token generation process completed! Your Lambda functions should now work properly." -ForegroundColor Green
                Write-Host ""
            }
            catch {
                Write-Host "Error in Step 3: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Make sure AWS CLI is configured and you have SSM permissions" -ForegroundColor Yellow
            }
        }
        
        "refresh" {
            try {
                Write-Host "Fetching current refresh token from SSM..." -ForegroundColor Yellow
                
                $RefreshTokenCmd = "aws ssm get-parameter --name '/fyers-api/refresh-token' --with-decryption --region ap-south-1 --query 'Parameter.Value' --output text"
                $CurrentRefreshToken = Invoke-Expression $RefreshTokenCmd
                
                if ([string]::IsNullOrEmpty($CurrentRefreshToken)) {
                    Write-Host "Could not fetch refresh token from SSM" -ForegroundColor Red
                    continue
                }
                
                # Generate app hash
                $AppHashInput = "${ClientId}:${AppSecret}"
                $SHA256 = [System.Security.Cryptography.SHA256]::Create()
                $HashBytes = $SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($AppHashInput))
                $AppHash = [System.BitConverter]::ToString($HashBytes).Replace("-", "").ToLower()
                
                # Refresh token request
                $TokenUrl = "https://api.fyers.in/api/v2/token"
                $Body = @{
                    grant_type = "refresh_token"
                    appIdHash = $AppHash
                    refresh_token = $CurrentRefreshToken
                } | ConvertTo-Json
                
                $Headers = @{
                    "Content-Type" = "application/json"
                }
                
                Write-Host "Refreshing access token..." -ForegroundColor Yellow
                
                $Response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $Body -Headers $Headers
                
                if ($Response.s -eq "ok") {
                    $NewAccessToken = $Response.access_token
                    
                    # Update SSM with new access token
                    $UpdateCmd = "aws ssm put-parameter --name '/fyers-api/access-token' --value '$NewAccessToken' --type SecureString --overwrite --region ap-south-1"
                    $UpdateResult = Invoke-Expression $UpdateCmd
                    
                    Write-Host ""
                    Write-Host "Token Refresh Successful!" -ForegroundColor Green
                    Write-Host "New Access Token: $NewAccessToken" -ForegroundColor Cyan
                    Write-Host "✓ Updated in SSM Parameter Store"
                    Write-Host ""
                } else {
                    Write-Host "Token refresh failed: $($Response.message)" -ForegroundColor Red
                    Write-Host "You may need to run the full authorization flow (step1, step2, step3)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "Error refreshing token: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        "exit" {
            Write-Host "Goodbye!" -ForegroundColor Green
            break
        }
        
        default {
            Write-Host "Invalid command. Please use: step1, step2, step3, refresh, or exit" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}
