# ALTERNATIVE: Using AWS Lambda Layer for Pandas

**This approach SKIPS the 5-minute local packaging step by using AWS's public Pandas layer.**

---

## 🎯 **COMPARISON:**

| Approach | Local Packaging Time | Internet Download | Complexity |
|----------|---------------------|-------------------|------------|
| **Original (package-analytics.ps1)** | 5 minutes | 60 MB Pandas | Low |
| **Lambda Layer (this guide)** | 30 seconds | 15 KB function only | Medium |

---

## 🚀 **DEPLOYMENT STEPS (2 minutes total):**

### **Step 1: Package Lambda Function Only (30 seconds)**

```powershell
cd "d:\Price Feed Parser\deployment"
.\package-analytics-layer.ps1
```

This creates a **tiny 15 KB ZIP** with just your Python code (no Pandas).

---

### **Step 2: Update Terraform to Use Public Layer**

Edit `infra/main-mvp.tf` - find the analytics Lambda resource and add the layer:

```hcl
resource "aws_lambda_function" "analytics" {
  filename         = "${path.module}/../deployment/lambda_analytics.zip"
  function_name    = "${var.project_name}-${var.environment}-analytics"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_analytics.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/../deployment/lambda_analytics.zip")
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 1536

  # ADD THIS: Use public AWS Lambda Layer for Pandas
  layers = [
    "arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python311:14"
  ]

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.ohlcv_data.id
      CSV_PREFIX     = "analytics/csv"
    }
  }

  tags = merge(local.common_tags, {
    Purpose  = "DataAnalytics"
    FreeTier = "Yes"
  })
}
```

---

### **Step 3: Deploy**

```powershell
cd ..\infra
terraform apply -var="notification_email=you@domain.com"
```

**Done!** AWS downloads Pandas layer automatically during deployment.

---

## 📋 **AWS Lambda Layer ARNs (by Region):**

If you're NOT in `ap-south-1`, use the correct ARN:

| Region | Pandas Layer ARN |
|--------|------------------|
| **ap-south-1** (Mumbai) | `arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python311:14` |
| us-east-1 (N. Virginia) | `arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python311:14` |
| us-west-2 (Oregon) | `arn:aws:lambda:us-west-2:336392948345:layer:AWSSDKPandas-Python311:14` |
| eu-west-1 (Ireland) | `arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python311:14` |

Full list: https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html

---

## ✅ **PROS OF LAMBDA LAYER:**

- ✅ **Faster deployment** (30 seconds vs 5 minutes)
- ✅ **No local Pandas installation** needed
- ✅ **Smaller package size** (15 KB vs 45 MB)
- ✅ **AWS manages updates** (Pandas version maintained by AWS)
- ✅ **Same cost** ($0.00 - still free tier)

---

## ⚠️ **CONS OF LAMBDA LAYER:**

- ❌ **Version lock** - You use AWS's Pandas version (currently 2.0.3)
- ❌ **Regional dependency** - Must use correct ARN for your region
- ❌ **Less control** - Can't customize Pandas version

---

## 🎯 **RECOMMENDATION:**

### **Use Lambda Layer if:**
- You want **fastest deployment** (2 minutes total)
- You don't want to install Pandas locally
- You're okay with AWS's Pandas version

### **Use Local Packaging if:**
- You need a **specific Pandas version**
- You want **full control** over dependencies
- 5 minutes packaging time is acceptable

---

## 📝 **COMPLETE LAYER DEPLOYMENT:**

```powershell
# Step 1: Package function only (30 seconds)
cd "d:\Price Feed Parser\deployment"
.\package-analytics-layer.ps1

# Step 2: Update Terraform (add 'layers' to analytics Lambda)
# Edit infra/main-mvp.tf as shown above

# Step 3: Deploy (2 minutes)
cd ..\infra
terraform apply -var="notification_email=you@domain.com"

# Step 4: Test
cd ..\examples
python query_analytics.py
```

---

## 🔄 **SWITCHING BETWEEN APPROACHES:**

You can switch anytime:

**From Layer → Local Package:**
1. Run `.\package-analytics.ps1` (creates full ZIP)
2. Remove `layers = [...]` from `main-mvp.tf`
3. Run `terraform apply`

**From Local Package → Layer:**
1. Run `.\package-analytics-layer.ps1` (creates small ZIP)
2. Add `layers = [...]` to `main-mvp.tf`
3. Run `terraform apply`

---

## 💡 **WHICH SHOULD YOU USE?**

**I recommend the Lambda Layer approach** because:
- 4x faster (2 min vs 10 min total)
- No need to install Pandas on your computer
- AWS maintains the layer (security updates)
- Same $0.00 cost

**Want to use it?** I can update the Terraform file for you! Just say "use lambda layer" and I'll make the change. 🚀
