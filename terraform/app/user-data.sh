#!/bin/bash

# HITL Platform - EC2 User Data Script
# Configures instance for serving React frontend from S3

set -e

# Configuration from Terraform template variables
S3_BUCKET_NAME="${s3_bucket_name}"
AWS_REGION="${aws_region}"
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"
LAMBDA_FUNCTION_URL="${lambda_function_url}"

# Logging
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "Starting HITL Platform EC2 configuration..."
echo "S3 Bucket: $S3_BUCKET_NAME"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"

# Set environment variables for services
cat > /etc/environment << EOF
S3_BUCKET_NAME=$S3_BUCKET_NAME
AWS_DEFAULT_REGION=$AWS_REGION
HITL_S3_BUCKET=$S3_BUCKET_NAME
ENVIRONMENT=$ENVIRONMENT
PROJECT_NAME=$PROJECT_NAME
EOF

# Source environment
source /etc/environment

# If using base Amazon Linux 2 AMI, install required packages
if [ ! -f "/usr/bin/nginx" ]; then
    echo "Installing nginx and dependencies..."
    yum update -y
    # Install nginx using Amazon Linux Extras (required for AL2)
    amazon-linux-extras install -y nginx1
    yum install -y awscli
    systemctl enable nginx
fi

# Configure nginx with complete server block
echo "Configuring nginx server block..."
cat > /etc/nginx/conf.d/default.conf << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/hitl;
    index index.html index.htm;

    # Serve static files
    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "public, max-age=3600";
    }

    # Proxy API calls to Lambda
    location /api/ {
        proxy_pass $LAMBDA_FUNCTION_URL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 30;
        proxy_send_timeout 30;
        proxy_read_timeout 30;
    }

    # Health check endpoints
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    location /health-detailed {
        proxy_pass $LAMBDA_FUNCTION_URL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10;
        proxy_send_timeout 10;
        proxy_read_timeout 10;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
}
EOF

# Get EC2 instance metadata using IMDSv2 and inject into nginx config
echo "Injecting EC2 instance metadata into nginx configuration..."
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)

echo "Instance ID: $INSTANCE_ID"
echo "Availability Zone: $AVAILABILITY_ZONE" 
echo "Instance Type: $INSTANCE_TYPE"

# Add headers to location / block in nginx config (only once)
sed -i "/try_files.*index.html/a\\        add_header X-Instance-ID $INSTANCE_ID always;" /etc/nginx/conf.d/default.conf

# Create web directory and S3 sync configuration
echo "Setting up web directory and S3 sync configuration..."
mkdir -p /var/www/hitl
mkdir -p /etc/hitl
chown nginx:nginx /var/www/hitl

# Download helper scripts from S3
echo "Downloading helper scripts from S3..."
SCRIPTS_BUCKET="${s3_bucket_name}"
aws s3 cp s3://$SCRIPTS_BUCKET/scripts/sync-from-s3.sh /usr/local/bin/sync-from-s3.sh --region=${aws_region} || {
    echo "ERROR: Could not download sync-from-s3.sh from S3"
    exit 1
}

aws s3 cp s3://$SCRIPTS_BUCKET/scripts/health-check.sh /usr/local/bin/health-check.sh --region=${aws_region} || {
    echo "ERROR: Could not download health-check.sh from S3"
    exit 1
}

# Set up cron job for S3 sync (every 2 minutes)
echo "*/2 * * * * root source /etc/environment; /usr/local/bin/sync-from-s3.sh" > /etc/cron.d/s3-sync

# Set up health check cron job (every minute)
echo "* * * * * root /usr/local/bin/health-check.sh" > /etc/cron.d/health-check

# Make sure scripts are executable
chmod +x /usr/local/bin/sync-from-s3.sh
chmod +x /usr/local/bin/health-check.sh

# Create log directory
mkdir -p /var/log/hitl

# Initial S3 sync to get React build
echo "Performing initial S3 sync..."
if ! /usr/local/bin/sync-from-s3.sh; then
    echo "ERROR: Initial S3 sync failed - no fallback content will be created"
    exit 1
fi
echo "Initial S3 sync completed successfully"

# Generate initial health check
echo "Generating initial health check..."
/usr/local/bin/health-check.sh || true

# Test nginx configuration
echo "Testing nginx configuration..."
if nginx -t; then
    echo "nginx configuration is valid"
    systemctl start nginx
    systemctl enable nginx
    echo "nginx started successfully"
else
    echo "nginx configuration test failed"
    systemctl status nginx || true
fi

# Start and enable CloudWatch agent if available
if [ -f "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl" ]; then
    echo "Starting CloudWatch agent..."
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config -m ec2 -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
fi

# Set up log rotation for our custom logs
cat > /etc/logrotate.d/hitl << 'EOF'
/var/log/hitl/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 root root
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF

echo "EC2 instance configuration completed successfully!"
echo "Services status:"
systemctl status nginx --no-pager -l || true
echo "S3 sync status:"
ls -la /var/www/hitl/ || true

# Signal completion to CloudFormation/Auto Scaling (if needed)
# This would be used with CloudFormation CreationPolicy or ASG lifecycle hooks
echo "User data script completed at $(date)"