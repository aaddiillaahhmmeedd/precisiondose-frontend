#!/bin/bash

#############################################
# PrecisionDose.in Automated Deployment Script
# Run this on a fresh Ubuntu 22.04 server
#############################################

set -e  # Exit on any error

echo "=========================================="
echo "PrecisionDose.in Automated Deployment"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use: sudo bash deploy.sh)"
    exit 1
fi

print_info "Starting deployment process..."
echo ""

# Step 1: Collect required information
echo "=========================================="
echo "Configuration Setup"
echo "=========================================="
echo ""

read -p "Enter your OpenAI API key: " OPENAI_KEY
read -p "Enter database password (create a secure one): " DB_PASSWORD
read -p "Enter your domain name (e.g., precisiondosage.in): " DOMAIN_NAME
read -p "Enter your email for SSL certificate: " EMAIL

echo ""
print_warning "Please confirm your settings:"
echo "Domain: $DOMAIN_NAME"
echo "Email: $EMAIL"
echo "OpenAI Key: ${OPENAI_KEY:0:20}..."
echo "DB Password: [HIDDEN]"
echo ""
read -p "Are these correct? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_error "Deployment cancelled. Please run the script again."
    exit 1
fi

echo ""
print_info "Configuration confirmed. Starting deployment..."
echo ""

# Step 2: Update system
echo "=========================================="
echo "Step 1/10: Updating System"
echo "=========================================="
apt update && apt upgrade -y
print_success "System updated"
echo ""

# Step 3: Install dependencies
echo "=========================================="
echo "Step 2/10: Installing Dependencies"
echo "=========================================="
apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx \
    postgresql postgresql-contrib git curl ufw fail2ban
print_success "Dependencies installed"
echo ""

# Step 4: Install Node.js
echo "=========================================="
echo "Step 3/10: Installing Node.js"
echo "=========================================="
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
print_success "Node.js installed ($(node --version))"
echo ""

# Step 5: Configure PostgreSQL
echo "=========================================="
echo "Step 4/10: Setting Up Database"
echo "=========================================="
sudo -u postgres psql << EOF
CREATE DATABASE precisiondose;
CREATE USER precisiondose_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE precisiondose TO precisiondose_user;
EOF
print_success "Database created and configured"
echo ""

# Step 6: Deploy Backend
echo "=========================================="
echo "Step 5/10: Deploying Backend"
echo "=========================================="

# Create directory
mkdir -p /var/www/precisiondose
cd /var/www/precisiondose

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python packages
pip install --upgrade pip
pip install fastapi uvicorn[standard] pydantic python-multipart openai \
    psycopg2-binary sqlalchemy python-dotenv boto3 python-jose[cryptography] \
    passlib[bcrypt]

# Create .env file
cat > .env << EOF
OPENAI_API_KEY=$OPENAI_KEY
DATABASE_URL=postgresql://precisiondose_user:$DB_PASSWORD@localhost:5432/precisiondose
SECRET_KEY=$(openssl rand -hex 32)
ENVIRONMENT=production
DEBUG=False
ALLOWED_ORIGINS=https://$DOMAIN_NAME,https://www.$DOMAIN_NAME
AWS_S3_BUCKET=precisiondose-uploads
AWS_REGION=us-east-1
EOF

print_success "Backend environment configured"

# Create backend file (simplified version)
cat > precisiondose_backend.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="PrecisionDose AI API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"service": "PrecisionDose AI", "status": "operational"}

@app.get("/api/v1/health")
async def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

print_info "Backend files created. You need to upload your full backend code."

# Create systemd service
cat > /etc/systemd/system/precisiondose.service << EOF
[Unit]
Description=PrecisionDose API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/precisiondose
Environment="PATH=/var/www/precisiondose/venv/bin"
EnvironmentFile=/var/www/precisiondose/.env
ExecStart=/var/www/precisiondose/venv/bin/uvicorn precisiondose_backend:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl start precisiondose
systemctl enable precisiondose

print_success "Backend service started"
echo ""

# Step 7: Deploy Frontend
echo "=========================================="
echo "Step 6/10: Deploying Frontend"
echo "=========================================="

mkdir -p /var/www/precisiondose-frontend
cd /var/www/precisiondose-frontend

# Create a simple landing page
cat > index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PrecisionDose AI</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0;
            padding: 20px;
        }
        .container {
            background: white;
            padding: 60px 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 600px;
        }
        h1 {
            color: #667eea;
            margin: 0 0 20px 0;
            font-size: 36px;
        }
        p {
            color: #4a5568;
            line-height: 1.8;
            margin: 0 0 30px 0;
        }
        .status {
            display: inline-block;
            padding: 12px 24px;
            background: #48bb78;
            color: white;
            border-radius: 8px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 PrecisionDose AI</h1>
        <p>Your personalized medication assistant is now deployed!</p>
        <div class="status">✓ System Operational</div>
        <p style="margin-top: 30px; font-size: 14px; color: #a0aec0;">
            Replace this page with your full application frontend.
        </p>
    </div>
</body>
</html>
HTMLEOF

print_success "Frontend deployed"
print_info "Upload your full frontend files to /var/www/precisiondose-frontend/"
echo ""

# Step 8: Configure Nginx
echo "=========================================="
echo "Step 7/10: Configuring Nginx"
echo "=========================================="

cat > /etc/nginx/sites-available/$DOMAIN_NAME << EOF
upstream backend {
    server localhost:8000;
}

server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    location ~ /.well-known {
        allow all;
        root /var/www/precisiondose-frontend;
    }

    location / {
        root /var/www/precisiondose-frontend;
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    client_max_body_size 10M;
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and restart
nginx -t
systemctl restart nginx

print_success "Nginx configured"
echo ""

# Step 9: Configure Firewall
echo "=========================================="
echo "Step 8/10: Configuring Firewall"
echo "=========================================="

ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'

print_success "Firewall configured"
echo ""

# Step 10: Install SSL Certificate
echo "=========================================="
echo "Step 9/10: Installing SSL Certificate"
echo "=========================================="

print_warning "Make sure DNS is pointing to this server!"
print_info "A record: $DOMAIN_NAME -> $(curl -s ifconfig.me)"
echo ""
read -p "Is DNS configured? (yes/no): " DNS_READY

if [ "$DNS_READY" = "yes" ]; then
    certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME \
        --non-interactive --agree-tos --email $EMAIL --redirect
    print_success "SSL certificate installed!"
else
    print_warning "SSL certificate skipped. Run this command later:"
    echo "certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME"
fi
echo ""

# Step 11: Set Up Automated Backups
echo "=========================================="
echo "Step 10/10: Setting Up Backups"
echo "=========================================="

mkdir -p /root/backups

cat > /root/backup.sh << 'BACKUPEOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/backups"
sudo -u postgres pg_dump precisiondose > $BACKUP_DIR/db_$DATE.sql
tar -czf $BACKUP_DIR/app_$DATE.tar.gz /var/www/precisiondose
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
BACKUPEOF

chmod +x /root/backup.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /root/backup.sh >> /var/log/backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet") | crontab -

print_success "Automated backups configured (daily at 2 AM)"
echo ""

# Final Summary
echo ""
echo "=========================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
print_success "Your PrecisionDose AI system is now deployed!"
echo ""
echo "Access your site at:"
if [ "$DNS_READY" = "yes" ]; then
    echo "  https://$DOMAIN_NAME"
else
    echo "  http://$DOMAIN_NAME (after DNS setup)"
fi
echo ""
echo "Backend API:"
echo "  https://$DOMAIN_NAME/api/v1/"
echo ""
echo "Server IP: $(curl -s ifconfig.me)"
echo ""
echo "=========================================="
echo "IMPORTANT NEXT STEPS:"
echo "=========================================="
echo ""
echo "1. Upload your full backend code to:"
echo "   /var/www/precisiondose/"
echo ""
echo "2. Upload your frontend files to:"
echo "   /var/www/precisiondose-frontend/"
echo ""
echo "3. Restart services:"
echo "   systemctl restart precisiondose"
echo "   systemctl restart nginx"
echo ""
echo "4. Test your deployment:"
echo "   curl https://$DOMAIN_NAME"
echo "   curl https://$DOMAIN_NAME/api/v1/health"
echo ""
echo "=========================================="
echo "USEFUL COMMANDS:"
echo "=========================================="
echo ""
echo "View backend logs:"
echo "  journalctl -u precisiondose -f"
echo ""
echo "Restart backend:"
echo "  systemctl restart precisiondose"
echo ""
echo "Check service status:"
echo "  systemctl status precisiondose"
echo "  systemctl status nginx"
echo ""
echo "Manual backup:"
echo "  /root/backup.sh"
echo ""
echo "=========================================="
echo ""
print_success "Deployment script completed successfully!"
print_info "Check the full deployment guide for additional configuration."
echo ""
