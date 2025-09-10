# Fyers API Manual Token Generator - Minimal Working Version
param(
    [string]$Command = ""
)

$ErrorActionPreference = "Stop"

# Configuration - Update these values
$ClientId = "FYFZ9P3PYF-100"  # Replace with your actual Client ID
$AppSecret = "K3TOU7KO0Y"     # Replace with your actual App Secret  
$RedirectUri = "https://127.0.0.1:3000/"

function Show-Menu {
    Write-Host "===== Fyers API Manual Token Generator =====" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available Commands:" -ForegroundColor Yellow
    Write-Host "1. step1    - Generate authorization URL"
    Write-Host "2. step2    - Exchange auth code for tokens"
    Write-Host "3. step3    - Update SSM parameters"
    Write-Host "4. refresh  - Refresh access token"
    Write-Host "5. exit     - Exit"
    Write-Host ""
}

function Invoke-Step1 {
    try {
        # Generate app hash
        $AppHashInput = "${ClientId}:${AppSecret}"
        $SHA256 = [System.Security.Cryptography.SHA256]::Create()
        $HashBytes = $SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($AppHashInput))
        $AppHash = [System.BitConverter]::ToString($HashBytes).Replace("-", "").ToLower()
        
        # Create authorization URL
        Add-Type -AssemblyName System.Web
        $EncodedRedirectUri = [System.Web.HttpUtility]::UrlEncode($RedirectUri)
        $AuthUrl = "https://api-t2.fyers.in/api/v3/generate-authcode?client_id=${ClientId}&redirect_uri=${EncodedRedirectUri}&response_type=code&state=sample&scope=openid"
        
        Write-Host "Step 1: Authorization URL Generated" -ForegroundColor Green
        Write-Host "App Hash: $AppHash" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Authorization URL:" -ForegroundColor Yellow
        Write-Host $AuthUrl
        Write-Host ""
        Write-Host "1. Open this URL in your browser"
        Write-Host "2. Login and authorize"
        Write-Host "3. Copy the auth_code from redirected URL"
        Write-Host "4. Run: .\manual_token_generator_minimal.ps1 step2"
        Write-Host ""
        
        # Save app hash to file for next step
        $AppHash | Out-File -FilePath "app_hash.txt" -Encoding UTF8
        Write-Host "App hash saved to app_hash.txt" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Step2 {
    try {
        # Load app hash
        if (Test-Path "app_hash.txt") {
            $AppHash = Get-Content "app_hash.txt"
        }
        else {
            Write-Host "Please run step1 first" -ForegroundColor Red
            return
        }
        
        $AuthCode = Read-Host "Enter the auth_code from URL"
        
        $TokenUrl = "https://api-t2.fyers.in/vagator/v2/generate_access_token"
        $Body = @{
            grant_type = "authorization_code"
            appIdHash  = $AppHash
            code       = $AuthCode
        } | ConvertTo-Json
        
        $Headers = @{ "Content-Type" = "application/json" }
        
        Write-Host "Exchanging auth code for tokens..." -ForegroundColor Yellow
        
        $Response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $Body -Headers $Headers
        
        if ($Response.s -eq "ok") {
            Write-Host "Tokens Generated Successfully!" -ForegroundColor Green
            Write-Host "Access Token: $($Response.access_token)" -ForegroundColor Cyan
            Write-Host "Refresh Token: $($Response.refresh_token)" -ForegroundColor Cyan
            
            # Save tokens to file
            @{
                access_token  = $Response.access_token
                refresh_token = $Response.refresh_token
            } | ConvertTo-Json | Out-File -FilePath "tokens.json" -Encoding UTF8
            
            Write-Host "Tokens saved to tokens.json" -ForegroundColor Green
            Write-Host "Run: .\manual_token_generator_minimal.ps1 step3" -ForegroundColor Yellow
        }
        else {
            Write-Host "Failed: $($Response.message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Step3 {
    try {
        if (-not (Test-Path "tokens.json")) {
            Write-Host "Please run step2 first" -ForegroundColor Red
            return
        }
        
        $Tokens = Get-Content "tokens.json" | ConvertFrom-Json
        
        Write-Host "Updating SSM parameters..." -ForegroundColor Yellow
        
        # Update access token
        aws ssm put-parameter --name '/fyers-api/access-token' --value $Tokens.access_token --type SecureString --overwrite --region ap-south-1
        
        # Update refresh token  
        aws ssm put-parameter --name '/fyers-api/refresh-token' --value $Tokens.refresh_token --type SecureString --overwrite --region ap-south-1
        
        Write-Host "SSM Parameters Updated Successfully!" -ForegroundColor Green
        Write-Host "Process completed!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Refresh {
    try {
        Write-Host "Fetching refresh token from SSM..." -ForegroundColor Yellow
        
        $RefreshToken = aws ssm get-parameter --name '/fyers-api/refresh-token' --with-decryption --region ap-south-1 --query 'Parameter.Value' --output text
        
        # Generate app hash
        $AppHashInput = "${ClientId}:${AppSecret}"
        $SHA256 = [System.Security.Cryptography.SHA256]::Create()
        $HashBytes = $SHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($AppHashInput))
        $AppHash = [System.BitConverter]::ToString($HashBytes).Replace("-", "").ToLower()
        
        $TokenUrl = "https://api-t2.fyers.in/vagator/v2/generate_access_token"
        $Body = @{
            grant_type    = "refresh_token"
            appIdHash     = $AppHash
            refresh_token = $RefreshToken
        } | ConvertTo-Json
        
        $Headers = @{ "Content-Type" = "application/json" }
        
        Write-Host "Refreshing access token..." -ForegroundColor Yellow
        
        $Response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $Body -Headers $Headers
        
        if ($Response.s -eq "ok") {
            aws ssm put-parameter --name '/fyers-api/access-token' --value $Response.access_token --type SecureString --overwrite --region ap-south-1
            
            Write-Host "Token Refresh Successful!" -ForegroundColor Green
            Write-Host "New Access Token: $($Response.access_token)" -ForegroundColor Cyan
        }
        else {
            Write-Host "Refresh failed: $($Response.message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
if ($Command -eq "") {
    Show-Menu
    $Command = Read-Host "Enter command"
}

switch ($Command.ToLower()) {
    "step1" { Invoke-Step1 }
    "step2" { Invoke-Step2 }
    "step3" { Invoke-Step3 }
    "refresh" { Invoke-Refresh }
    "exit" { Write-Host "Goodbye!" -ForegroundColor Green }
    default { 
        Write-Host "Invalid command. Use: step1, step2, step3, refresh, or exit" -ForegroundColor Red
        Show-Menu
    }
}
