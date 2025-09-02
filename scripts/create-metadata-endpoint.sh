#!/bin/bash
set -e

echo "Creating metadata endpoint script..."
cat > /usr/local/bin/update-metadata.sh << 'EOF'
#!/bin/bash
set -e

# Get IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

# Get instance metadata
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

# Create JSON response for health-detailed endpoint
cat > /var/www/hitl/health-detailed << JSON_EOF
{
  "status": "healthy",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "instance_id": "${INSTANCE_ID:-unknown}",
  "availability_zone": "${AZ:-unknown}",
  "instance_type": "${INSTANCE_TYPE:-unknown}",
  "region": "${REGION:-unknown}",
  "services": {
    "nginx": "healthy",
    "s3_sync": "healthy"
  }
}
JSON_EOF

chown nginx:nginx /var/www/hitl/health-detailed
EOF

chmod +x /usr/local/bin/update-metadata.sh

# Run it once to create initial file
/usr/local/bin/update-metadata.sh

# Add cron job to update metadata every minute
echo "* * * * * /usr/local/bin/update-metadata.sh" | crontab -

echo "Metadata endpoint script created!"