#!/bin/bash
set -e

echo "Installing OpenResty (nginx + Lua) for runtime metadata fetching..."
# Add OpenResty repository
wget -O openresty.repo https://openresty.org/package/amazon/openresty.repo
mv openresty.repo /etc/yum.repos.d/
# Install OpenResty
yum install -y openresty
systemctl enable openresty

# Install lua-resty-http module for HTTP requests in Lua
echo "Installing lua-resty-http module..."
cd /tmp
wget https://github.com/ledgetech/lua-resty-http/archive/refs/tags/v0.17.1.tar.gz
tar -zxf v0.17.1.tar.gz
mkdir -p /usr/local/openresty/lualib/resty
cp -r lua-resty-http-0.17.1/lib/resty/http* /usr/local/openresty/lualib/resty/
rm -rf /tmp/lua-resty-http-0.17.1 /tmp/v0.17.1.tar.gz

echo "Creating directory structure..."
mkdir -p /var/www/hitl
echo '<h1>HITL Platform Ready</h1>' > /var/www/hitl/index.html
chown -R nobody:nobody /var/www/hitl

echo "Configuring OpenResty..."
mkdir -p /usr/local/openresty/nginx/conf/conf.d
cat > /usr/local/openresty/nginx/conf/conf.d/default.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/hitl;
    index index.html;

    # Health check endpoint served directly by nginx
    location /health {
        access_log off;
        return 200 'healthy\n';
        add_header Content-Type text/plain;
    }

    # Detailed health endpoint with instance metadata
    location = /health-detailed {
        access_log off;
        alias /var/www/hitl/health-detailed;
        add_header Content-Type application/json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # API routes proxy to Lambda (placeholder - configured by user-data)
    location /api/ {
        # Placeholder - actual proxy configuration added by user-data script
        return 503;
    }

    # Default route serves React app with runtime instance ID
    location / {
        access_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            
            -- First get the IMDSv2 token
            local token_res, err = httpc:request_uri("http://169.254.169.254/latest/api/token", {
                method = "PUT",
                headers = { ["X-aws-ec2-metadata-token-ttl-seconds"] = "21600" },
                timeout = 1000  -- 1 second timeout
            })
            
            if token_res and token_res.status == 200 then
                -- Then get instance ID with token
                local id_res, err = httpc:request_uri("http://169.254.169.254/latest/meta-data/instance-id", {
                    headers = { ["X-aws-ec2-metadata-token"] = token_res.body },
                    timeout = 1000  -- 1 second timeout
                })
                if id_res and id_res.status == 200 then
                    ngx.header["X-Instance-ID"] = id_res.body
                else
                    ngx.header["X-Instance-ID"] = "metadata-error"
                end
            else
                ngx.header["X-Instance-ID"] = "token-error"
            end
        }
        try_files $uri $uri/ /index.html;
    }

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection '1; mode=block';
}
EOF

# Update main nginx.conf to include our conf.d files
sed -i '/http {/a\    include /usr/local/openresty/nginx/conf/conf.d/*.conf;' /usr/local/openresty/nginx/conf/nginx.conf

echo "OpenResty installation and configuration complete!"