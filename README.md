# HITL Platform - Complete Documentation

A production-ready, FedRAMP High-compliant static frontend deployment solution for federal cloud environments. This project demonstrates secure React application deployment using AWS services without CloudFront, ECR, ECS, or Fargate dependencies.

**Now with both Terraform and CloudFormation deployment options!**

## 📚 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Quick Start](#-quick-start)
- [Deployment Guide](#-deployment-guide)
- [Infrastructure Components](#-infrastructure-components)
- [Key Features](#-key-features)
- [Security & Compliance](#-security--compliance)
- [Monitoring & Operations](#-monitoring--operations)
- [Cost Analysis](#-cost-analysis)
- [Troubleshooting](#-troubleshooting)
- [Development Workflow](#-development-workflow)
- [Testing](#-testing)
- [FAQ](#-faq)

## 🏗️ Architecture Overview

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet Users                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   AWS WAF v2    │ ← DDoS Protection, Rate Limiting
                    │  8 Rule Groups  │ ← Geo-blocking, SQL/XSS Prevention
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   ALB (HTTPS)   │ ← TLS 1.3, ACM Certificates
                    │  Load Balancer  │ ← Health Checks, Path Routing
                    └────────┬────────┘
                             │
            ┌────────────────▼────────────────┐
            │         Auto Scaling Group      │
            │        EC2 Instances            │ ← Frontend serving
            │        (Golden AMI)             │
            └────────┬─────────────────┬──────┘
                     │                 │
            ┌────────▼──────┐  ┌───────▼─────────┐
            │  Lambda API   │  │   S3 Bucket     │
            │  (Backend)    │  │  Static Assets  │ ← Content sync
            │  (Serverless) │  │  (Private)      │
            └───────────────┘  └─────────────────┘
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **VPC Endpoints** | Private subnets with VPC endpoints | Secure AWS API access without NAT Gateway |
| **Golden AMI** | EC2 Image Builder automated pipeline | No internet access during boot, consistent configuration |
| **Local Content Serving** | nginx serves from EC2 local storage | Fast responses, no S3 request costs |
| **OpenResty** | nginx + Lua for metadata injection | Runtime instance ID headers without app changes |
| **S3 Sync** | Cron job every 2 minutes | Automatic content updates with visual monitoring |

### Multi-Tier Security Architecture

```
Layer 1: WAF          → Rate limiting, geo-blocking, attack prevention
Layer 2: ALB          → TLS 1.3 encryption, certificate validation
Layer 3: Security Groups → Least-privilege network access
Layer 4: IAM Roles    → No credentials in code, minimal permissions
Layer 5: Encryption   → S3 (AES-256), EBS (encrypted), TLS in transit
Layer 6: Monitoring   → CloudWatch, VPC Flow Logs, access logging
```

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools and versions
- AWS CLI v2 (configured with credentials)
- Node.js >= 22.x
- Git

# For Terraform deployment:
- Terraform >= 1.5.0
- jq (JSON processor)
- GNU Make

# For CloudFormation deployment:
- Bash shell
```

### 30-Second Deployment (if you know what you're doing)

#### Option A: Using Terraform
```bash
# Clone and deploy everything
git clone <repository> && cd deploy-static-frontend
cd demo-app && npm install && npm run build && cd ..
cd terraform/vpc && terraform init && terraform apply -auto-approve
cd ../ami && terraform init && terraform apply -auto-approve
# Wait 15-20 minutes for AMI build
cd ../app && terraform init && terraform apply -auto-approve
terraform output application_url
```

#### Option B: Using CloudFormation
```bash
# Clone and deploy everything with automatic AMI build
git clone <repository> && cd deploy-static-frontend
cd demo-app && npm install && npm run build && cd ..
./cloudformation/deploy.sh -e dev --build-ami
# Wait 15-20 minutes for AMI build, then access the URL shown
```

### Step-by-Step Deployment

Choose your preferred Infrastructure as Code tool:

- **[Terraform Deployment](#terraform-deployment)** - Original implementation
- **[CloudFormation Deployment](#cloudformation-deployment)** - AWS native alternative

## Terraform Deployment

#### 1️⃣ Build React Application
```bash
cd demo-app
npm install
npm run build  # Creates build/ directory with static files
cd ..
```

#### 2️⃣ Deploy VPC Infrastructure
```bash
cd terraform/vpc
terraform init
terraform apply -auto-approve
# Creates: VPC, subnets, IGW, VPC endpoints, security groups
```

#### 3️⃣ Build Golden AMI (Automated)
```bash
cd ../ami
terraform init
terraform apply -auto-approve
# Automatically triggers AMI build via EC2 Image Builder
# Wait 15-20 minutes for completion
# Check status: aws imagebuilder list-images --query 'imageList[0].state.status'
```

#### 4️⃣ Deploy Application Stack
```bash
cd ../app
terraform init
terraform apply -auto-approve
# Creates: ALB, ASG, Lambda, S3, CloudWatch
# Automatically uploads React app and scripts
```

#### 5️⃣ Access Application
```bash
# Get URL
terraform output application_url
# Example: http://hitl-dev-alb-123456.us-east-1.elb.amazonaws.com

# Or with custom domain (if configured)
# https://hitl.your-domain.com
```

## CloudFormation Deployment

#### 1️⃣ Build React Application
```bash
cd demo-app
npm install
npm run build  # Creates build/ directory with static files
cd ..
```

#### 2️⃣ Deploy All Stacks with AMI Build (Recommended)
```bash
# Deploy all stacks and build AMI automatically
./cloudformation/deploy.sh -e dev --build-ami

# The script will:
# 1. Deploy VPC stack (network foundation)
# 2. Deploy AMI stack (creates S3 buckets and triggers Image Builder)
# 3. Wait for AMI build completion (15-20 minutes)
# 4. Deploy Application stack with new AMI (ALB, ASG, Lambda)
# 5. Upload React app and sync to EC2 instances
```

#### 3️⃣ Alternative: Deploy Stacks Individually
```bash
# Option to deploy stacks one by one

# Deploy VPC stack first
./cloudformation/deploy.sh -e dev -s vpc

# Deploy AMI stack and trigger build
./cloudformation/deploy.sh -e dev -s ami --build-ami
# Wait for AMI build completion (15-20 minutes)

# Deploy Application stack with built AMI
./cloudformation/deploy.sh -e dev -s app
```

#### 4️⃣ React App Deployment (Automatic)
```bash
# The deploy.sh script automatically:
# 1. Builds the React app (if not already built)
# 2. Uploads to S3 bucket
# 3. Syncs to EC2 instances via cron job

# Manual upload if needed:
S3_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name hitl-cf-dev-app \
  --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
  --output text)
aws s3 sync ./demo-app/build/ s3://$S3_BUCKET/build/
```

#### 5️⃣ Access Application
```bash
# The deploy script will show the application URL
# Or retrieve it manually:
aws cloudformation describe-stacks \
  --stack-name hitl-dev-app \
  --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
  --output text
```

#### CloudFormation Management Commands
```bash
# Check stack status
./cloudformation/deploy.sh -e dev -a status

# Update existing stacks (includes Lambda updates)
./cloudformation/deploy.sh -e dev -s app -a update

# Force instance refresh after updates
# (Automatically triggered on app stack updates)

# Delete all stacks (WARNING: Destructive)
./cloudformation/deploy.sh -e dev -a delete -s all

# Deploy to different environments
./cloudformation/deploy.sh -e stage -s all
./cloudformation/deploy.sh -e prod -s all

# Get help
./cloudformation/deploy.sh -h
```

## 📋 Deployment Guide

This project now supports both **Terraform** and **CloudFormation** deployments with identical functionality. Choose the tool that best fits your organization's standards and expertise.

### Infrastructure as Code Options

| Tool | Location | Command | Benefits |
|------|----------|---------|----------|
| **Terraform** | `terraform/` | `terraform apply` | Multi-cloud, HCL syntax, mature ecosystem |
| **CloudFormation** | `cloudformation/` | `./deploy.sh` | AWS-native, YAML/JSON, stack management |

Both implementations maintain the same 3-layer architecture with proper separation of concerns.

### ⚠️ CRITICAL: Deployment Order

**Must deploy in this exact sequence:**

1. **VPC Stack** → Network foundation
2. **Image Builder** → Creates golden AMI (15-20 min)
3. **Application Stack** → Uses VPC and AMI

### Why Separate States/Stacks?

We maintain **3 separate state files (Terraform) or stacks (CloudFormation)** for:

1. **Isolation**: VPC changes don't trigger app redeployment
2. **Team Separation**: Network team owns VPC, app team owns application
3. **Flexibility**: Can deploy to existing VPC or create new one
4. **Blast Radius**: Limits impact of destroy operations

#### Terraform State Files:
```
terraform/vpc/terraform.tfstate         → VPC infrastructure
terraform/ami/terraform.tfstate → AMI builder
terraform/app/terraform.tfstate         → Application
```

#### CloudFormation Stacks:
```
hitl-{env}-vpc           → VPC infrastructure stack
hitl-{env}-ami → AMI builder stack
hitl-{env}-app           → Application stack
```

### Environment-Specific Deployments

#### Using Terraform:
```bash
# Development
ENVIRONMENT=dev make deploy-vpc deploy-app

# Staging
ENVIRONMENT=stage make deploy-vpc deploy-app

# Production
ENVIRONMENT=prod make deploy-vpc deploy-app
```

#### Using CloudFormation:
```bash
# Development
./cloudformation/deploy.sh -e dev -s all

# Staging
./cloudformation/deploy.sh -e stage -s all

# Production
./cloudformation/deploy.sh -e prod -s all
```

## 🔧 Infrastructure Components

### VPC Infrastructure 
**Terraform:** `terraform/vpc/`  
**CloudFormation:** `cloudformation/vpc-stack/`

| Component | Configuration | Purpose |
|-----------|--------------|---------|
| **VPC** | 10.10.0.0/16 CIDR | Network isolation |
| **Public Subnets** | 2 AZs, /24 each | Load balancer, NAT-free outbound |
| **Private Subnets** | 2 AZs, /24 each | EC2 instances, Lambda functions |
| **Internet Gateway** | Single IGW | Outbound internet via public subnets |
| **VPC Endpoints** | S3, SSM, CloudWatch, EC2 | Private AWS API access |
| **Security Groups** | Least-privilege | Network access control |

### Golden AMI Pipeline
**Terraform:** `terraform/ami/`  
**CloudFormation:** `cloudformation/ami-stack/`

**Fully Automated Build Process:**
1. `terraform apply` or `cloudformation deploy` triggers pipeline
2. EC2 Image Builder launches build instance
3. Installs OpenResty, scripts, security hardening
4. Creates AMI and cleans up
5. Outputs AMI ID for app stack

**AMI Contents:**
- Amazon Linux 2 (latest)
- OpenResty (nginx + Lua)
- AWS CLI & SSM Agent
- CloudWatch Agent
- S3 sync scripts
- Health check generators
- Security hardening

### Application Stack
**Terraform:** `terraform/app/`  
**CloudFormation:** `cloudformation/app-stack/`

| Component | Configuration | Features |
|-----------|--------------|----------|
| **ALB** | Multi-AZ, HTTPS, public subnets | Path-based routing `/api/*` → Lambda, health checks |
| **Auto Scaling Group** | 2-4 instances, t3.small, private subnets | Automatic scaling, instance refresh on updates |
| **Launch Template** | Golden AMI, user data | Instance configuration, automatic refresh |
| **Lambda Function** | Node.js 22, 128MB, private subnets | API backend with full endpoint suite |
| **S3 Bucket** | Private, encrypted | Static assets with automatic EC2 sync |
| **CloudWatch** | Logs, metrics, alarms | Monitoring via VPC endpoints |
| **WAF** (optional) | 8 rule groups | Security protection |

#### Lambda API Endpoints
The Lambda function provides these REST API endpoints (routed via ALB):

| Endpoint | Method | Description | Response |
|----------|--------|-------------|----------|
| `/api/health` | GET | Basic health check | `"healthy"` |
| `/api/health-detailed` | GET | Detailed system status | System metrics, memory, uptime |
| `/api/status` | GET | API operational status | Environment, timestamp |
| `/api/info` | GET | Platform information | Features, deployment type |
| `/api/metrics` | GET | Application metrics | Server info, performance data |

## 🎯 Key Features

### Visual Load Balancing Proof

The React application displays real-time infrastructure information:

```javascript
// Frontend displays real-time infrastructure data:
{
  "instanceId": "i-0abc123def456789",    // Current EC2 instance
  "availabilityZone": "us-east-1a",      // Instance location
  "region": "us-east-1",                 // AWS region
  "lambdaAPI": {                         // Lambda backend (via ALB routing)
    "instanceId": "lambda-hitl-cf-dev-api-46263324",
    "type": "lambda",
    "zone": "us-east-1b",
    "status": "active"
  },
  "s3SyncStatus": {                      // Sync monitoring
    "lastSync": "2024-01-15T10:30:00Z",
    "secondsAgo": 45,
    "status": "healthy"                  // Green/Yellow/Red indicator
  }
}
```

### S3 Sync Status Monitoring

**Visual Indicators in UI:**
- 🟢 **Green**: Synced < 5 minutes ago (healthy)
- 🟡 **Yellow**: Synced 5-10 minutes ago (warning)
- 🔴 **Red**: Synced > 10 minutes ago (critical)

**Implementation Details:**
- Cron job runs every 2 minutes
- Writes timestamp to `/var/www/hitl/.last-sync`
- Health endpoint reads and calculates age
- React app fetches and displays with color coding

### Health Monitoring Endpoints

#### Simple Health Check (`/health`)
```bash
curl http://$ALB_DNS/health
# Returns: healthy
```

#### Detailed Health (`/health-detailed`)
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "instance": {
    "id": "i-0abc123def456789",
    "type": "t3.small",
    "availability_zone": "us-east-1a"
  },
  "services": {
    "openresty": {
      "status": "active",
      "uptime_seconds": 3600
    },
    "s3_sync": {
      "last_sync": "2024-01-15T10:28:00Z",
      "seconds_since_last_sync": 120
    }
  },
  "system": {
    "load_average": "0.15 0.10 0.08",
    "memory_used_percent": 35.2,
    "disk_used": "28%"
  }
}
```

### OpenResty Runtime Headers

Every response includes instance metadata:
```http
X-Instance-ID: i-0abc123def456789
X-Availability-Zone: us-east-1a
X-Region: us-east-1
```

## 🔒 Security & Compliance

### FedRAMP High Controls Implementation

| Control | Description | Implementation |
|---------|-------------|----------------|
| **AC-2** | Account Management | IAM roles with least privilege, no root access |
| **AC-3** | Access Enforcement | Security groups, NACLs, IAM policies |
| **AU-2** | Audit Events | CloudWatch, VPC Flow Logs, CloudTrail |
| **AU-12** | Audit Generation | All API calls logged to CloudTrail |
| **CM-2** | Baseline Configuration | Golden AMI with security hardening |
| **CM-8** | System Component Inventory | Resource tagging, AWS Config |
| **IA-5** | Authenticator Management | TLS 1.3, ACM certificates |
| **SC-7** | Boundary Protection | WAF, security groups, VPC isolation |
| **SC-8** | Transmission Confidentiality | HTTPS/TLS 1.3 encryption |
| **SC-28** | Protection at Rest | S3 encryption, EBS encryption |
| **SI-4** | System Monitoring | CloudWatch, GuardDuty integration ready |

### WAF Configuration (8 Security Rules)

```yaml
1. RateLimitRule:
   - 2000 requests/5 minutes per IP
   - Automatic 240-second block

2. GeoRestrictionRule:
   - Allow: US only
   - Block: All other countries

3. IPReputationList:
   - AWS managed IP reputation list
   - Blocks known malicious IPs

4. CoreRuleSet:
   - OWASP Top 10 protection
   - SQL injection prevention
   - XSS attack prevention

5. KnownBadInputs:
   - Blocks known attack patterns
   - Log4j vulnerability protection

6. SizeRestrictions:
   - Body: 8KB max
   - URI: 2KB max

7. SQLiRule:
   - SQL injection detection
   - Database attack prevention

8. XSSRule:
   - Cross-site scripting prevention
   - JavaScript injection blocking
```

### Security Best Practices Implemented

✅ **Network Security**
- EC2 instances and Lambda in private subnets
- No direct internet access for compute resources
- All traffic through ALB/WAF in public subnets
- VPC endpoints for secure AWS API access
- No SSH keys (Systems Manager only)

✅ **Data Security**
- Encryption at rest (S3, EBS)
- Encryption in transit (TLS 1.3)
- No sensitive data in logs
- Private S3 bucket only

✅ **Access Control**
- IMDSv2 enforced (no IMDSv1)
- IAM roles, no hardcoded credentials
- Least privilege permissions
- MFA enforced for console access

✅ **Compliance Features**
- Complete audit logging
- Automated patching via AMI rebuilds
- Immutable infrastructure
- No runtime configuration changes

## 📊 Monitoring & Operations

### CloudWatch Dashboards

**Automatic dashboard creation includes:**
- ALB metrics (requests, latency, errors)
- EC2 metrics (CPU, network, disk)
- Lambda metrics (invocations, errors, duration)
- Custom metrics (S3 sync status)

### Log Groups

| Log Group | Purpose | Retention |
|-----------|---------|-----------|
| `/aws/ec2/nginx/access` | Web server access logs | 30 days |
| `/aws/ec2/nginx/error` | Web server errors | 30 days |
| `/aws/ec2/hitl/sync` | S3 synchronization logs | 30 days |
| `/aws/lambda/hitl-dev-api` | Lambda function logs | 30 days |
| `/aws/wafv2/hitl-dev` | WAF blocked requests | 30 days |

### Alarms & Notifications

```yaml
Critical Alarms:
  - ALB unhealthy targets > 0
  - EC2 CPU > 80% for 5 minutes
  - Lambda errors > 1% of invocations
  - Certificate expiry < 30 days

Warning Alarms:
  - S3 sync age > 10 minutes
  - Memory usage > 80%
  - Disk usage > 80%
```

### Operational Commands

```bash
# Check instance S3 sync status
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /var/www/hitl/.last-sync"]'

# Force immediate S3 sync
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo /usr/local/bin/sync-from-s3.sh"]'

# View sync logs
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -50 /var/log/hitl/sync.log"]'

# Check OpenResty status
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status openresty"]'

# Trigger instance refresh (rolling update)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name hitl-dev-web-asg \
  --preferences '{"InstanceWarmup": 300, "MinHealthyPercentage": 50}'
```

## 💰 Cost Analysis

### Monthly Cost Breakdown (Development Environment)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| **ALB** | Always on, 2 AZs | $16.00 |
| **EC2** | 2x t3.small (730 hrs) | $30.36 |
| **EBS** | 2x 8GB gp3 | $1.60 |
| **Lambda** | <1M requests | $1.00 |
| **S3** | 10GB storage + requests | $0.25 |
| **Data Transfer** | 10GB out | $0.90 |
| **CloudWatch** | Logs + metrics | $5.00 |
| **Route53** | 1 hosted zone | $0.50 |
| **Total** | | **~$55.61** |

### Cost Optimization Strategies

| Strategy | Savings | Implementation |
|----------|---------|----------------|
| **VPC Endpoints vs NAT** | $45/month | Use VPC endpoints instead of NAT Gateway |
| **No CloudFront** | $10/month | Direct ALB serving |
| **Local Serving** | $5/month | Eliminate S3 GET requests |
| **Right-sizing** | $20/month | t3.small vs t3.medium |
| **Spot Instances** | 70% | For dev/test environments |
| **Scheduled Scaling** | 60% | Shutdown non-prod at night |

### Production Scaling Costs

```yaml
Small (100 users/day):
  - 2x t3.small: $30/month
  - Total: ~$60/month

Medium (1,000 users/day):
  - 4x t3.medium: $120/month
  - Total: ~$150/month

Large (10,000 users/day):
  - 8x t3.large: $480/month
  - CloudFront: $50/month
  - Total: ~$600/month
```

## 🐛 Troubleshooting

### Common Issues & Solutions

#### Issue: S3 Sync Not Updating index.html
**Symptom**: React app deployment doesn't reflect changes
**Root Cause**: AWS S3 sync has inconsistent behavior with index.html
**Solution**: Added explicit copy after sync in `sync-from-s3.sh`:
```bash
# Force update index.html (workaround)
aws s3 cp s3://$S3_BUCKET/index.html /var/www/hitl/index.html --region $REGION || true
```

#### Issue: S3 Sync Status Shows "Unknown"
**Symptom**: UI shows "S3 Sync: Unknown ⚠"
**Causes & Solutions**:
1. New instance still initializing → Wait 2-3 minutes
2. Sync script failed → Check CloudWatch logs
3. IAM permissions issue → Verify EC2 role has S3 access

#### Issue: Terraform AMI Build Timeout
**Symptom**: Terraform times out during Image Builder apply
**Solution**: Use longer timeout:
```bash
terraform apply -timeout=30m
```

#### Issue: Launch Template Not Using New AMI
**Symptom**: New instances using old AMI despite rebuild
**Solution**: Run terraform apply on app stack to update launch template:
```bash
cd terraform/app && terraform apply -auto-approve
```

#### Issue: Instances Failing Health Checks
**Symptom**: ALB marks instances unhealthy
**Checks**:
```bash
# Verify security group allows ALB → EC2:80
aws ec2 describe-security-groups --group-ids sg-xxx

# Check nginx is running
aws ssm send-command --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status openresty"]'

# Check health endpoint
curl http://<instance-ip>/health
```

#### Issue: HTTPS Not Working
**Symptom**: Certificate errors or HTTPS unavailable
**Note**: Cannot use ACM certificates with ALB DNS names
**Solutions**:
1. Use custom domain with Route53
2. Import existing certificate
3. Use HTTP only for development

### Debug Commands Cheatsheet

```bash
# Get all instance IDs
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=hitl-dev-web" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text

# Check S3 bucket contents
aws s3 ls s3://hitl-dev-frontend-xxx/ --recursive

# View ALB target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:xxx

# Check Lambda function logs
aws logs tail /aws/lambda/hitl-dev-api --follow

# Monitor Auto Scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name hitl-dev-web-asg \
  --max-items 10
```

## 🔄 Development Workflow

### Updating React Application

```bash
# 1. Make changes in demo-app/src/
cd demo-app
npm start  # Local development

# 2. Build production bundle
npm run build

# 3. Deploy to S3
cd ../terraform/app
terraform apply -target=aws_s3_object.react_app -auto-approve

# 4. Changes appear within 2 minutes (or force sync via SSM)
```

### Updating Lambda Function

```bash
# 1. Edit lambda-backend/index.js
cd lambda-backend

# 2. Build deployment package
./build.sh

# 3. Deploy
cd ../terraform/app
terraform apply -target=aws_lambda_function.api -auto-approve
```

### Updating Infrastructure

```bash
# For infrastructure changes
cd terraform/app
terraform plan  # Review changes
terraform apply -auto-approve

# For AMI updates
cd terraform/ami
# Increment version in main.tf
terraform apply -auto-approve  # Triggers rebuild

# Then update app to use new AMI
cd ../app
terraform apply -auto-approve
```

### Blue/Green Deployment Process

```bash
# 1. Build new AMI with updated app
cd terraform/ami
# Update version number
terraform apply -auto-approve

# 2. Create new launch template version
cd ../app
terraform apply -auto-approve

# 3. Start instance refresh (rolling update)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name hitl-dev-web-asg \
  --preferences '{"InstanceWarmup": 300, "MinHealthyPercentage": 50}'

# 4. Monitor progress
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name hitl-dev-web-asg
```

## 🧪 Testing

### Infrastructure Tests

#### Terraform:
```bash
# Validate Terraform
cd terraform/vpc && terraform validate
cd ../app && terraform validate
cd ../ami && terraform validate

# Dry run
terraform plan -detailed-exitcode
```

#### CloudFormation:
```bash
# Validate templates
aws cloudformation validate-template \
  --template-body file://cloudformation/vpc-stack/vpc-template.yaml

aws cloudformation validate-template \
  --template-body file://cloudformation/ami-stack/ami-template.yaml

aws cloudformation validate-template \
  --template-body file://cloudformation/app-stack/app-template.yaml

# Check stack status
./cloudformation/deploy.sh -e dev -a status
```

### Application Tests

```bash
# Health checks
curl -f http://$ALB_DNS/health
curl http://$ALB_DNS/health-detailed | jq .

# Load balancing verification (run 10 times)
for i in {1..10}; do
  curl -s http://$ALB_DNS/ | jq -r .instanceId
done | sort | uniq -c

# API endpoint testing
curl http://$ALB_DNS/api/health
curl http://$ALB_DNS/api/metrics
curl http://$ALB_DNS/api/demo
```

### Security Tests

```bash
# TLS verification (if HTTPS enabled)
openssl s_client -connect $DOMAIN:443 -tls1_3

# WAF testing (should be blocked)
curl -X POST http://$ALB_DNS/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "test=<script>alert('xss')</script>"

# Rate limit testing
for i in {1..3000}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_DNS/
done | grep -c 403  # Should see 403s after 2000 requests
```

### Performance Tests

```bash
# Response time
curl -w "@curl-format.txt" -o /dev/null -s http://$ALB_DNS/

# Load testing with Apache Bench
ab -n 1000 -c 10 http://$ALB_DNS/

# Memory and CPU monitoring
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=hitl-dev-web-asg \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T23:59:59Z \
  --period 3600 \
  --statistics Average
```

## 📁 Complete Project Structure

```
deploy-static-frontend/
├── demo-app/                     # React frontend application
│   ├── src/
│   │   ├── App.tsx              # Main app with S3 sync monitoring
│   │   └── index.tsx            
│   ├── build/                   # Generated static files
│   └── package.json
│
├── lambda-backend/              # Serverless API
│   ├── index.js                # Lambda handler
│   ├── package.json
│   └── build.sh                # Build script
│
├── terraform/                   # Terraform Infrastructure as Code
│   ├── vpc/                    # Network layer (State 1)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfstate
│   │
│   ├── ami/          # AMI pipeline (State 2)
│   │   ├── main.tf            # EC2 Image Builder config
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfstate
│   │
│   └── app/                    # Application layer (State 3)
│       ├── main.tf
│       ├── alb.tf             # Load balancer
│       ├── auto-scaling.tf    # ASG and launch template
│       ├── lambda.tf          # Serverless backend
│       ├── s3.tf              # Static storage
│       ├── s3-scripts.tf      # Script uploads
│       ├── monitoring.tf      # CloudWatch
│       ├── waf.tf             # Security rules
│       └── terraform.tfstate
│
├── cloudformation/             # CloudFormation Infrastructure as Code
│   ├── deploy.sh              # Deployment script for all stacks
│   ├── vpc-stack/             # Network layer (Stack 1)
│   │   ├── vpc-template.yaml
│   │   ├── parameters-dev.json
│   │   ├── parameters-stage.json
│   │   └── parameters-prod.json
│   │
│   ├── ami-stack/   # AMI pipeline (Stack 2)
│   │   ├── ami-template.yaml
│   │   ├── parameters-dev.json
│   │   ├── parameters-stage.json
│   │   └── parameters-prod.json
│   │
│   └── app-stack/             # Application layer (Stack 3)
│       ├── app-template.yaml
│       ├── parameters-dev.json
│       ├── parameters-stage.json
│       └── parameters-prod.json
│
├── scripts/                    # Deployment scripts
│   ├── install-nginx.sh       # OpenResty installation
│   ├── sync-from-s3.sh       # S3 content sync with index.html fix
│   └── generate-health.sh    # Health endpoint generator
│
├── environments/              # Terraform environment configs
│   ├── dev.tfvars
│   ├── vpc-dev.tfvars
│   ├── stage.tfvars
│   └── prod.tfvars
│
├── public/                    # Static assets
├── .github/                   # GitHub Actions workflows
├── Makefile                   # Build automation
└── README.md                  # Complete documentation
```

## 🔨 Makefile Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make check-deps` | Verify prerequisites installed |
| `make build` | Build Lambda and React apps |
| `make build-frontend` | Build React application only |
| `make build-lambda` | Build Lambda function only |
| `make deploy-vpc` | Deploy VPC infrastructure |
| `make deploy-ami-pipeline` | Deploy AMI builder |
| `make deploy-app` | Deploy application stack |
| `make get-latest-ami` | Get most recent AMI ID |
| `make update-ami-id` | Update tfvars with new AMI |
| `make clean` | Remove build artifacts |
| `make destroy-all` | Tear down all infrastructure |
| `make status` | Show deployment status |
| `make validate` | Validate all configurations |

## ❓ FAQ

### Q: Why can't I use HTTPS with the ALB DNS name?
**A:** AWS Certificate Manager (ACM) cannot issue certificates for AWS-owned domains (*.elb.amazonaws.com). You must use a custom domain or accept HTTP-only access.

### Q: Should I use Terraform or CloudFormation?
**A:** Both options are fully supported and provide identical functionality:
- **Use Terraform** if you prefer multi-cloud support, HCL syntax, or already use Terraform
- **Use CloudFormation** if you prefer AWS-native tools, YAML/JSON templates, or want tighter AWS integration
- Both maintain the same 3-layer architecture with proper separation of concerns

### Q: Why do we need 3 separate Terraform state files / CloudFormation stacks?
**A:** Separation provides isolation, reduces blast radius, and allows different teams to manage different layers. VPC rarely changes, while the app layer changes frequently.

### Q: Why use VPC Endpoints instead of NAT Gateway for private subnets?
**A:** NAT Gateway costs $45/month plus data transfer fees. VPC Endpoints provide secure AWS API access for private subnets at a fraction of the cost while maintaining better security isolation.

### Q: How does the S3 sync fix work?
**A:** AWS S3 sync has a bug where index.html doesn't always update. We work around this by explicitly copying index.html after the sync operation.

### Q: Can I use this in production?
**A:** Yes, this architecture is production-ready and FedRAMP High compliant. For production, you should:
- Use a custom domain with HTTPS
- Enable WAF rules
- Configure CloudWatch alarms
- Implement backup strategies
- Use Reserved Instances for cost savings

### Q: How do I update the React app without downtime?
**A:** Upload new files to S3, and they'll automatically sync to all instances within 2 minutes. The ALB ensures zero-downtime during instance updates.

### Q: What happens if an instance fails?
**A:** Auto Scaling automatically replaces failed instances. The ALB removes unhealthy instances from rotation, ensuring continuous service availability.

### Q: How do I scale for more traffic?
**A:** Auto Scaling automatically adds instances based on CPU utilization. You can also manually adjust desired capacity or modify scaling policies.

### Q: Is the data encrypted?
**A:** Yes, all data is encrypted:
- At rest: S3 (AES-256), EBS (encrypted volumes)
- In transit: TLS 1.3 for all HTTPS traffic
- No sensitive data in logs or environment variables

### Q: How much does this cost to run?
**A:** Development environment costs ~$55/month. Production with 4 instances costs ~$150/month. Significant savings from no NAT Gateway and no CloudFront.

## 📚 Additional Resources

### AWS Documentation
- [EC2 Image Builder Guide](https://docs.aws.amazon.com/imagebuilder/)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Systems Manager](https://docs.aws.amazon.com/systems-manager/)
- [WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)

### Related Projects
- [AWS FedRAMP Quickstart](https://aws.amazon.com/quickstart/architecture/fedramp/)
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)

### Compliance Resources
- [FedRAMP High Baseline](https://www.fedramp.gov/documents/)
- [NIST 800-53 Controls](https://nvd.nist.gov/800-53)

## 📝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and test thoroughly
4. Run validation: `make validate`
5. Commit changes: `git commit -m 'Add amazing feature'`
6. Push branch: `git push origin feature/amazing-feature`
7. Open Pull Request with detailed description

### Development Guidelines
- Follow existing code patterns
- Add tests for new features
- Update documentation
- Ensure security best practices
- Test in dev environment first

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 👥 Support

For issues, questions, or contributions:
1. Check this documentation and FAQ
2. Search [GitHub Issues](https://github.com/your-org/deploy-static-frontend/issues)
3. Create new issue with:
   - Environment details
   - Error messages
   - Steps to reproduce
   - Expected vs actual behavior

## 🎯 Project Goals

This project demonstrates:
- ✅ Secure React deployment without CloudFront/ECS
- ✅ FedRAMP High compliance capabilities
- ✅ Cost-optimized architecture (~$55/month)
- ✅ Visual proof of load balancing
- ✅ Automated infrastructure deployment (Terraform & CloudFormation)
- ✅ Golden AMI pipeline automation with EC2 Image Builder
- ✅ Real-time S3 sync monitoring with visual status indicators
- ✅ Zero-downtime deployments with automatic instance refresh
- ✅ Lambda API backend with ALB routing
- ✅ Complete security controls
- ✅ Production-ready architecture

---

**Built for Federal Cloud Environments** 🇺🇸

*This solution enables secure, compliant, and cost-effective deployment of modern web applications in highly regulated environments without relying on commonly restricted services.*

**Version:** 2.0.0 | **Last Updated:** 2025-09-03 | **Status:** Production Ready

### Recent Updates (v2.0.0)
- Full CloudFormation implementation alongside Terraform
- Automatic AMI build integration with `--build-ami` flag
- Lambda API endpoints with proper ALB routing
- Automatic instance refresh on application updates
- Fixed OpenResty configuration and S3 sync permissions
- Enhanced deployment script with comprehensive error handling