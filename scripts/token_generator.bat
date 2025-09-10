@echo off
echo.
echo ===================================================
echo   Manual Fyers Token Generator - Quick Commands
echo ===================================================
echo.

:menu
echo Choose an option:
echo.
echo 1. Generate Authorization URL
echo 2. Get Tokens from Auth Code
echo 3. Update SSM Parameters
echo 4. Refresh Existing Token
echo 5. Check Current Token Status
echo 6. Test Token Validity
echo 7. View CloudWatch Logs
echo 8. Exit
echo.
set /p choice="Enter your choice (1-8): "

if "%choice%"=="1" goto generate_url
if "%choice%"=="2" goto get_tokens
if "%choice%"=="3" goto update_ssm
if "%choice%"=="4" goto refresh_token
if "%choice%"=="5" goto check_status
if "%choice%"=="6" goto test_token
if "%choice%"=="7" goto view_logs
if "%choice%"=="8" goto exit
echo Invalid choice, please try again.
goto menu

:generate_url
echo.
echo =====================================
echo   Step 1: Generate Authorization URL
echo =====================================
echo.
set /p client_id="Enter your Fyers Client ID: "
echo.
echo Your authorization URL:
echo https://api-t2.fyers.in/api/v3/generate-authcode?client_id=%client_id%^&redirect_uri=https://trade.fyers.in/api-login/redirect-to-app^&response_type=code^&state=sample_state
echo.
echo Instructions:
echo 1. Copy the URL above and open it in your browser
echo 2. Login to your Fyers account
echo 3. After login, copy the 'auth_code' from the redirect URL
echo 4. Return here and choose option 2
echo.
pause
goto menu

:get_tokens
echo.
echo =====================================
echo   Step 2: Get Tokens from Auth Code
echo =====================================
echo.
echo This step requires Python. Make sure you have:
echo - Python installed
echo - requests library (pip install requests)
echo.
set /p auth_code="Enter the auth code from redirect URL: "
echo.
echo Running Python script...
python manual_token_generator.py --step 2 --auth-code %auth_code%
echo.
pause
goto menu

:update_ssm
echo.
echo =====================================
echo   Step 3: Update SSM Parameters
echo =====================================
echo.
set /p access_token="Enter Access Token: "
set /p refresh_token="Enter Refresh Token: "
echo.
echo Updating AWS SSM parameters...
echo.
aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/access_token" --value "%access_token%" --type "SecureString" --overwrite
aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/refresh_token" --value "%refresh_token%" --type "SecureString" --overwrite
echo.
if %errorlevel%==0 (
    echo ✅ SSM parameters updated successfully!
) else (
    echo ❌ Error updating SSM parameters. Check AWS credentials.
)
echo.
pause
goto menu

:refresh_token
echo.
echo =====================================
echo   Step 4: Refresh Existing Token
echo =====================================
echo.
echo This will use the existing refresh token to get a new access token.
echo.
python manual_token_generator.py --refresh
echo.
pause
goto menu

:check_status
echo.
echo =====================================
echo   Check Current Token Status
echo =====================================
echo.
echo Checking SSM parameters...
echo.
aws ssm get-parameters --names "/stock-pipeline-mvp/fyers/access_token" "/stock-pipeline-mvp/fyers/refresh_token" "/stock-pipeline-mvp/fyers/client_id" --output table
echo.
pause
goto menu

:test_token
echo.
echo =====================================
echo   Test Token Validity
echo =====================================
echo.
echo Testing Lambda function...
echo.
aws lambda invoke --function-name stock-pipeline-mvp-ingestion --payload "{}" test_response.json
echo.
echo Response:
type test_response.json
echo.
del test_response.json
echo.
pause
goto menu

:view_logs
echo.
echo =====================================
echo   View CloudWatch Logs
echo =====================================
echo.
echo Recent Lambda logs:
echo.
aws logs filter-log-events --log-group-name "/aws/lambda/stock-pipeline-mvp-ingestion" --start-time %~1 --max-items 10
echo.
pause
goto menu

:exit
echo.
echo Thanks for using the Manual Token Generator!
echo.
exit /b 0
