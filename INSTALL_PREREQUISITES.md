# Prerequisites Installation Guide (Windows)

Before deploying your Stock Price Feed Parser, you need to install the required tools.

## Quick Installation (Recommended)

Use the automated setup script:
```powershell
.\scripts\install_prerequisites.ps1
```

## Manual Installation

### 1. Install AWS CLI

**Option A: Using winget (Windows 10/11)**
```powershell
winget install Amazon.AWSCLI
```

**Option B: Direct download**
1. Download from: https://aws.amazon.com/cli/
2. Run the installer
3. Restart PowerShell

**Verify installation:**
```powershell
aws --version
```

### 2. Install Terraform

**Option A: Using winget**
```powershell
winget install Hashicorp.Terraform
```

**Option B: Using Chocolatey**
```powershell
# Install Chocolatey first (if not installed)
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install Terraform
choco install terraform
```

**Option C: Manual download**
1. Download from: https://developer.hashicorp.com/terraform/downloads
2. Extract to a folder (e.g., `C:\terraform`)
3. Add to PATH environment variable

**Verify installation:**
```powershell
terraform version
```

### 3. Install Python (if not already installed)

**Check if Python is installed:**
```powershell
python --version
```

**If not installed:**
```powershell
winget install Python.Python.3.11
```

### 4. Configure AWS Credentials

Run AWS configuration:
```powershell
aws configure
```

Enter your AWS credentials:
- AWS Access Key ID: `[Your Access Key]`
- AWS Secret Access Key: `[Your Secret Key]`
- Default region name: `ap-south-1` (or your preferred region)
- Default output format: `json`

### 5. Verify Everything is Working

Run the deployment prerequisite check:
```powershell
cd deployment
.\deploy-mvp.ps1 -NotificationEmail "test@example.com" -WhatIf
```

## Troubleshooting

### AWS CLI Issues
- **Command not found**: Restart PowerShell after installation
- **Credentials error**: Run `aws configure` to set up credentials
- **Region issues**: Set default region with `aws configure set region ap-south-1`

### Terraform Issues
- **Command not found**: Check if Terraform is in your PATH
- **Version conflicts**: Use latest version (1.5+)
- **Permission errors**: Run PowerShell as Administrator

### Python Issues
- **pip not found**: Install Python with pip included
- **Package conflicts**: Use virtual environment

## Next Steps

After installing prerequisites:

1. **Configure environment**: `.\scripts\env_setup.ps1`
2. **Deploy infrastructure**: `.\deployment\deploy-mvp.ps1 -NotificationEmail "your-email@example.com"`
3. **Verify deployment**: Check AWS Console for created resources

## Getting AWS Credentials

If you don't have AWS credentials yet:

1. Sign up for AWS account: https://aws.amazon.com/
2. Go to IAM Console: https://console.aws.amazon.com/iam/
3. Create a new user with programmatic access
4. Attach policy: `AdministratorAccess` (for development)
5. Save the Access Key ID and Secret Access Key

⚠️ **Security Note**: For production, use more restrictive IAM policies.
