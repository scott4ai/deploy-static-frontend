#!/bin/bash
set -e
# Get IMDSv2 token first
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

# Use standard nginx document root
WEB_DIR="/var/www/html"

# Ensure directory exists
mkdir -p "$WEB_DIR"

# Check if we got the region, fail if not
if [ -z "$REGION" ]; then
    echo '<h1>HITL Platform - Metadata Service Error</h1><p>Failed to get region from 169.254.169.254 using IMDSv2</p>' > "$WEB_DIR/index.html"
    chown nginx:nginx "$WEB_DIR/index.html"
    exit 1
fi

S3_BUCKET=${S3_BUCKET_NAME:-}
if [ -z "$S3_BUCKET" ]; then
    S3_BUCKET=$(aws ec2 describe-tags --region $REGION --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=S3Bucket" --query 'Tags[0].Value' --output text)
fi

if [ "$S3_BUCKET" != "None" ] && [ -n "$S3_BUCKET" ]; then
    # Exclude health* files and .last-sync from deletion - these are dynamically generated locally
    if ! aws s3 sync s3://$S3_BUCKET/build/ "$WEB_DIR/" --region $REGION --delete --exclude "health*" --exclude ".last-sync"; then
        echo '<h1>HITL Platform - S3 Sync Failed</h1><p>Failed to sync from S3 bucket: '$S3_BUCKET'</p>' > "$WEB_DIR/index.html"
        chown nobody:nobody "$WEB_DIR/index.html" 2>/dev/null || chown nginx:nginx "$WEB_DIR/index.html" 2>/dev/null || true
        exit 1
    fi
    
    # Force update index.html specifically (workaround for S3 sync issue with this file)
    aws s3 cp s3://$S3_BUCKET/build/index.html "$WEB_DIR/index.html" --region $REGION || true
    
    # Write timestamp of successful sync
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$WEB_DIR/.last-sync"
    
    # Set proper ownership - try different web server users
    chown -R nobody:nobody "$WEB_DIR" 2>/dev/null || \
    chown -R nginx:nginx "$WEB_DIR" 2>/dev/null || \
    chown -R apache:apache "$WEB_DIR" 2>/dev/null || \
    chown -R www-data:www-data "$WEB_DIR" 2>/dev/null || true
else
    echo '<h1>HITL Platform - No S3 Bucket</h1><p>S3_BUCKET_NAME not set or S3Bucket tag not found</p>' > "$WEB_DIR/index.html"
    chown nobody:nobody "$WEB_DIR/index.html" 2>/dev/null || chown nginx:nginx "$WEB_DIR/index.html" 2>/dev/null || true
    exit 1
fi
