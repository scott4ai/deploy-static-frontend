#!/bin/bash

# HITL Platform - EC2 User Data Script (Custom AMI Version)
# Minimal configuration for pre-baked AMI with OpenResty already installed

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

echo "Starting HITL Platform EC2 configuration (Custom AMI)..."
echo "S3 Bucket: $S3_BUCKET_NAME"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"

# Set environment variables for services
cat > /etc/environment << EOF
S3_BUCKET_NAME=$S3_BUCKET_NAME
S3_BUCKET=$S3_BUCKET_NAME
AWS_DEFAULT_REGION=$AWS_REGION
HITL_S3_BUCKET=$S3_BUCKET_NAME
ENVIRONMENT=$ENVIRONMENT
PROJECT_NAME=$PROJECT_NAME
EOF

# Source environment
source /etc/environment

# Export the S3_BUCKET variable for scripts
export S3_BUCKET="$S3_BUCKET_NAME"

# Configure API proxy in OpenResty (replace placeholder with actual Lambda URL)
echo "Configuring API proxy to Lambda..."
if ! sed -i '/# Placeholder - actual proxy configuration added by user-data script/,/return 503/c\
        proxy_pass '"$LAMBDA_FUNCTION_URL"';\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_connect_timeout 30;\
        proxy_send_timeout 30;\
        proxy_read_timeout 30;' /usr/local/openresty/nginx/conf/conf.d/default.conf; then
    echo "Warning: Could not update API proxy configuration - placeholder may not exist"
fi

# Test OpenResty configuration
echo "Testing OpenResty configuration..."
if /usr/local/openresty/nginx/sbin/nginx -t; then
    echo "OpenResty configuration is valid"
    systemctl start openresty
    systemctl enable openresty
    echo "OpenResty started successfully"
else
    echo "OpenResty configuration test failed"
    systemctl status openresty || true
fi

# Get EC2 instance metadata using IMDSv2 and inject into nginx config
echo "Injecting EC2 instance metadata into nginx configuration..."
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

echo "Instance ID: $INSTANCE_ID"

# Instance ID is now fetched at runtime via Lua - no sed replacement needed

# Set up cron jobs for S3 sync and health checks
echo "Setting up cron jobs..."
cat > /etc/cron.d/s3-sync << 'EOF'
# S3 sync every 2 minutes
*/2 * * * * root source /etc/environment; /usr/local/bin/sync-from-s3.sh >> /var/log/s3-sync.log 2>&1

EOF

cat > /etc/cron.d/health-generation << 'EOF'  
# Health endpoint generation every minute
* * * * * root /usr/local/bin/generate-health.sh >/dev/null 2>&1

EOF

# Set proper permissions for cron files
chmod 644 /etc/cron.d/s3-sync
chmod 644 /etc/cron.d/health-generation

# Restart cron service to pick up new jobs
systemctl restart crond || service crond restart || true
echo "Cron jobs configured and service restarted"

# Initial S3 sync to get React build
echo "Performing initial S3 sync..."
if /usr/local/bin/sync-from-s3.sh; then
    echo "Initial S3 sync completed successfully"
else
    echo "Initial S3 sync failed, but continuing..."
fi

# Generate initial health check
echo "Generating initial health check..."
/usr/local/bin/generate-health.sh || true

# Start CloudWatch agent if available
if [ -f "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl" ]; then
    echo "Starting CloudWatch agent..."
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config -m ec2 -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
fi

echo "EC2 instance configuration completed successfully!"
echo "Services status:"
systemctl status openresty --no-pager -l || true
echo "S3 sync status:"
ls -la /var/www/hitl/ || true

echo "User data script completed at $(date)"