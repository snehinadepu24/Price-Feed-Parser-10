# 🔑 AWS Token Generator - Integration Guide

## Overview

The **AWS Token Generator** is now fully integrated into your existing Price Feed Parser infrastructure. No separate deployment needed - it's part of your existing AWS setup!

## 🚀 Quick Deployment

### Option 1: Deploy Everything Together (Recommended)
```powershell
# Deploy your entire pipeline with token generator included
cd infra
terraform apply -var="notification_email=your-email@example.com"
```

### Option 2: Use the Helper Script
```powershell
# Use the deployment script
.\scripts\deploy-token-generator.ps1 -NotificationEmail "your-email@example.com"
```

## 🌐 Daily Usage Workflow

### Every Morning (3 Simple Steps):

1. **🌐 Open Web UI**: 
   ```
   https://{api-gateway-id}.execute-api.ap-south-1.amazonaws.com/prod
   ```

2. **🔑 Generate Tokens**:
   - Enter your Fyers Client ID and App Secret
   - Click "Generate Login URL"
   - Login to Fyers in the popup
   - Paste the redirect URL
   - Click "Generate & Store Tokens"

3. **✅ Done!** Your pipeline automatically uses the new tokens

## 🏗️ Architecture Integration

### Added to Your Existing Infrastructure:
```
Existing Pipeline:
  Lambda Ingestion → S3 → CloudWatch
       ↓
  SSM Parameters

NEW Token Generator:
  Web UI → API Gateway → Lambda → SSM Parameters
                                      ↑
                              (Same parameters!)
```

### What Was Added:
- **Lambda Function**: `{project-name}-token-generator`
- **API Gateway**: Serves web UI and handles token requests
- **No new SSM parameters**: Uses your existing parameter structure

## 🔧 Technical Details

### Infrastructure Files Modified:
- ✅ `infra/main-mvp.tf` - Added token generator components
- ✅ `aws-token-generator/lambda_function.py` - Token generator backend
- ✅ `aws-token-generator/requirements.txt` - Dependencies

### AWS Services Used (All Free Tier):
- **API Gateway**: 1M free requests/month
- **Lambda**: 1M free requests/month
- **SSM Parameters**: Free for standard parameters

### SSM Parameters Updated:
```
/{project-name}/fyers/access_token     # Auto-stored by web UI
/{project-name}/fyers/refresh_token    # Auto-stored by web UI
/{project-name}/fyers/client_id        # Auto-stored by web UI
/{project-name}/fyers/app_secret       # Auto-stored by web UI
```

## 📱 Web UI Features

### 🎯 User-Friendly Interface:
- **Step-by-step guidance**
- **One-click Fyers login**
- **Automatic URL handling**
- **Real-time status updates**
- **Mobile responsive design**

### 🔒 Security Features:
- **HTTPS only**
- **No credential storage in browser**
- **Direct AWS SSM integration**
- **CORS protection**

## 🆚 Comparison: Before vs After

### Before (Manual Scripts):
```powershell
# Every morning you had to:
python scripts/manual_token_generator.py
aws ssm put-parameter --name "/stock-pipeline-mvp/fyers/access_token" --value "..."
# Complex command-line workflow
```

### After (Web UI):
```
1. Open bookmark → Web UI loads
2. Enter credentials → Click generate
3. Login to Fyers → Paste URL
4. Done! ✅
```

## 🔍 Monitoring & Troubleshooting

### View Logs:
```powershell
# Token generator logs
aws logs filter-log-events --log-group-name "/aws/lambda/{project-name}-token-generator"

# Pipeline logs  
aws logs filter-log-events --log-group-name "/aws/lambda/{project-name}-ingestion"
```

### Test Token Generator:
```powershell
# Test the API directly
curl https://{api-gateway-id}.execute-api.ap-south-1.amazonaws.com/prod
```

### Check SSM Parameters:
```powershell
aws ssm get-parameters --names \
  "/{project-name}/fyers/access_token" \
  "/{project-name}/fyers/refresh_token" \
  --with-decryption
```

## 🎯 Benefits

### ✅ **Integrated with Existing Setup**:
- No duplicate infrastructure
- Uses same SSM parameters
- Same monitoring and alerting

### ✅ **Zero Maintenance**:
- No local scripts to maintain
- No CLI dependencies
- Browser-based workflow

### ✅ **Free Tier Compliant**:
- All AWS services within free tier limits
- Cost: $0.00 - $1.00/month

### ✅ **Production Ready**:
- Error handling and logging
- CORS and security
- Mobile responsive

## 📚 Related Documentation

- 📖 **[Main README](../README.md)** - Full pipeline documentation
- 🏗️ **[Terraform Configuration](../infra/main-mvp.tf)** - Infrastructure code
- 🔑 **[Token Management Guide](../TOKEN_MANAGEMENT_GUIDE.md)** - Advanced token management

## 🆘 Support

### Common Issues:

1. **"Web UI not loading"**:
   ```powershell
   # Check if API Gateway was deployed
   terraform output token_generator_url
   ```

2. **"Token generation fails"**:
   ```powershell
   # Check Lambda logs
   aws logs filter-log-events --log-group-name "/aws/lambda/{project-name}-token-generator" --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **"Pipeline not using new tokens"**:
   ```powershell
   # Verify SSM parameters
   aws ssm get-parameters --names "/{project-name}/fyers/access_token" --with-decryption
   ```

---

🎉 **Your AWS-hosted token generator is ready!** No more daily command-line hassles - just open your browser and generate tokens in seconds.
