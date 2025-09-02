#!/bin/bash
set -e

echo "Setting up health endpoint generation..."

# Get IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# Get instance metadata
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Check OpenResty status
OPENRESTY_STATUS="inactive"
OPENRESTY_RESPONDING="false"
OPENRESTY_PID=""
OPENRESTY_UPTIME=""
OPENRESTY_VERSION=""

if systemctl is-active openresty >/dev/null 2>&1; then
    OPENRESTY_STATUS="active"
    OPENRESTY_RESPONDING="true"
    OPENRESTY_PID=$(systemctl show openresty -p MainPID --value 2>/dev/null || echo "")
    OPENRESTY_VERSION=$(/usr/local/openresty/nginx/sbin/nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || echo "unknown")
    
    # Get OpenResty start time and calculate uptime
    if [ -n "$OPENRESTY_PID" ] && [ "$OPENRESTY_PID" != "0" ]; then
        OPENRESTY_START_TIME=$(ps -o lstart= -p $OPENRESTY_PID 2>/dev/null | xargs -I {} date -d "{}" +%s 2>/dev/null || echo "0")
        if [ "$OPENRESTY_START_TIME" != "0" ]; then
            CURRENT_TIME=$(date +%s)
            OPENRESTY_UPTIME=$((CURRENT_TIME - OPENRESTY_START_TIME))
        fi
    fi
fi

# Check S3 sync status
S3_SYNC_STATUS="unknown"
LAST_SYNC=""
LAST_SYNC_SECONDS_AGO=""

# Check for .last-sync timestamp file
if [ -f /var/www/hitl/.last-sync ]; then
    LAST_SYNC=$(cat /var/www/hitl/.last-sync)
    if [ -n "$LAST_SYNC" ]; then
        S3_SYNC_STATUS="active"
        # Calculate seconds since last sync
        LAST_SYNC_EPOCH=$(date -d "$LAST_SYNC" +%s 2>/dev/null || echo "0")
        CURRENT_EPOCH=$(date +%s)
        if [ "$LAST_SYNC_EPOCH" != "0" ]; then
            LAST_SYNC_SECONDS_AGO=$((CURRENT_EPOCH - LAST_SYNC_EPOCH))
        fi
    fi
fi

# Get system metrics
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
MEMORY_USED=$(free -m | awk 'NR==2{printf "%.1f", $3*100/$2}')
DISK_USED=$(df -h / | awk 'NR==2{printf "%s", $5}')
UPTIME_SECONDS=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)

# Create health endpoint JSON for /health-detailed
cat > /var/www/hitl/health-detailed << JSON_EOF
{
  "status": "healthy",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "instance": {
    "id": "${INSTANCE_ID:-unknown}",
    "type": "${INSTANCE_TYPE:-unknown}",
    "availability_zone": "${AZ:-unknown}",
    "region": "${REGION:-unknown}",
    "private_ip": "${PRIVATE_IP:-unknown}"
  },
  "services": {
    "openresty": {
      "status": "${OPENRESTY_STATUS}",
      "responding": ${OPENRESTY_RESPONDING},
      "version": "${OPENRESTY_VERSION}",
      "pid": "${OPENRESTY_PID}",
      "uptime_seconds": ${OPENRESTY_UPTIME:-0}
    },
    "s3_sync": {
      "status": "${S3_SYNC_STATUS}",
      "last_sync": "${LAST_SYNC:-unknown}",
      "seconds_since_last_sync": ${LAST_SYNC_SECONDS_AGO:-null}
    }
  },
  "system": {
    "load_average": "${LOAD_AVG}",
    "memory_used_percent": ${MEMORY_USED:-0},
    "disk_used": "${DISK_USED}",
    "uptime_seconds": ${UPTIME_SECONDS}
  },
  "environment": {
    "environment": "${ENVIRONMENT:-dev}",
    "project": "${PROJECT_NAME:-hitl}",
    "s3_bucket": "${S3_BUCKET:-unknown}"
  }
}
JSON_EOF

# Set proper permissions
chown nobody:nobody /var/www/hitl/health-detailed 2>/dev/null || chown nginx:nginx /var/www/hitl/health-detailed 2>/dev/null || chown apache:apache /var/www/hitl/health-detailed 2>/dev/null || true

# The simple /health endpoint is handled by nginx location block
# No need to create a file for it

# Create the initial health endpoint
echo "Generating initial health endpoint..."
mkdir -p /var/www/hitl

# Set proper permissions
chown nobody:nobody /var/www/hitl/health-detailed 2>/dev/null || chown nginx:nginx /var/www/hitl/health-detailed 2>/dev/null || chown apache:apache /var/www/hitl/health-detailed 2>/dev/null || true

echo "Health endpoint generation complete!"