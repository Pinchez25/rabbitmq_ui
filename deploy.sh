#!/bin/bash

# Complete Next.js Local Deployment Script with RabbitMQ
set -e

echo "🚀 Starting Next.js local deployment with nginx..."

# clone the repository if not already done
if [ ! -d "RabbitScout" ]; then
    echo "Cloning RabbitScout repository..."
    git clone https://github.com/Ralve-org/RabbitScout.git
    cd RabbitScout
else
    echo "Repository already cloned. Navigating to RabbitScout directory..."
    cd RabbitScout
fi

# Configuration
APP_NAME="RabbitScout"
BUILD_DIR=".next"
DEPLOY_DIR="/var/www/$APP_NAME"
NGINX_CONFIG="/etc/nginx/sites-available/$APP_NAME.rabbitmq"
NGINX_ENABLED="/etc/nginx/sites-enabled/$APP_NAME.rabbitmq"
ENV_FILE=".env.production"

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Function to print coloured output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root for security reasons"
   exit 1
fi

# Check if yarn is installed
if ! command -v yarn &> /dev/null; then
    print_error "Yarn is not installed. Please install yarn first."
    exit 1
fi

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    print_warning "PM2 is not installed. Installing PM2..."
    npm install -g pm2
fi

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed. Please install nginx first:"
    echo "sudo apt update && sudo apt install nginx"
    exit 1
fi

# Create nginx sites directories if they don't exist
print_status "Setting up nginx directories..."
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

# Ensure the main nginx.conf includes sites-enabled
if ! grep -q "include /etc/nginx/sites-enabled" /etc/nginx/nginx.conf; then
    print_status "Adding sites-enabled include to nginx.conf..."
    sudo sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
fi

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    print_warning "$ENV_FILE not found. Creating from .env.local..."
    if [ -f ".env.local" ]; then
        cp .env.local $ENV_FILE
    else
        print_error "No environment file found. Please create $ENV_FILE with your variables."
        exit 1
    fi
fi

# Load environment variables
print_status "Loading environment variables..."
set -a
source $ENV_FILE
set +a

# Install dependencies
print_status "Installing dependencies..."
yarn install

# Install sharp for optimised image processing
print_status "Installing sharp for image optimisation..."
yarn add sharp

# Build the application
print_status "Building Next.js application..."
NODE_ENV=production yarn build

# Check if build was successful
if [ ! -d "$BUILD_DIR" ]; then
    print_error "Build failed. .next directory not found."
    exit 1
fi

# Create deployment directory
print_status "Setting up deployment directory..."
sudo mkdir -p $DEPLOY_DIR
sudo mkdir -p $DEPLOY_DIR/logs

# Set initial permissions for deployment directory
print_status "Setting deployment directory permissions..."
sudo chown -R $USER:www-data $DEPLOY_DIR
sudo chmod -R 775 $DEPLOY_DIR

# Stop existing PM2 process if running
print_status "Stopping existing processes..."
pm2 stop $APP_NAME 2>/dev/null || echo "No existing process found"
pm2 delete $APP_NAME 2>/dev/null || echo "No existing process to delete"

# Copy build files (standalone build)
print_status "Copying build files..."
# First copy standalone files
cp -r $BUILD_DIR/standalone/* $DEPLOY_DIR/
# Then ensure .next directory structure exists
mkdir -p $DEPLOY_DIR/.next
# Copy all .next contents to preserve the build structure
cp -r $BUILD_DIR/* $DEPLOY_DIR/.next/

# Copy public directory if it exists
if [ -d "public" ]; then
    cp -r public $DEPLOY_DIR/
fi

# Copy environment file
print_status "Copying environment configuration..."
cp $ENV_FILE $DEPLOY_DIR/.env.production

# Create PM2 ecosystem file
print_status "Creating PM2 configuration..."
cat > $DEPLOY_DIR/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: '$APP_NAME',
      script: 'server.js',
      cwd: '$DEPLOY_DIR',
      env: {
        NODE_ENV: 'production',
        PORT: 3456,
        NEXT_PUBLIC_RABBITMQ_HOST: '$NEXT_PUBLIC_RABBITMQ_HOST',
        NEXT_PUBLIC_RABBITMQ_PORT: '$NEXT_PUBLIC_RABBITMQ_PORT',
        NEXT_PUBLIC_RABBITMQ_VHOST: '$NEXT_PUBLIC_RABBITMQ_VHOST',
        RABBITMQ_USERNAME: '$RABBITMQ_USERNAME',
        RABBITMQ_PASSWORD: '$RABBITMQ_PASSWORD'
      },
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '1G',
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      log_file: './logs/combined.log',
      time: true,
      restart_delay: 4000,
      max_restarts: 10,
      min_uptime: '10s'
    }
  ]
}
EOF

# Ensure final permissions are correct
print_status "Final permission check..."
sudo chown -R $USER:www-data $DEPLOY_DIR
sudo chmod -R 775 $DEPLOY_DIR

# Start the application with PM2
print_status "Starting application with PM2..."
cd $DEPLOY_DIR
pm2 start ecosystem.config.js

# Create/update nginx configuration
print_status "Creating nginx configuration..."
sudo tee $NGINX_CONFIG > /dev/null << 'EOF'
server {
    listen 80;
    server_name rabbitmq.localhost;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types
        text/css
        text/javascript
        text/xml
        text/plain
        text/x-component
        application/javascript
        application/x-javascript
        application/json
        application/xml
        application/rss+xml
        application/atom+xml
        font/truetype
        font/opentype
        application/vnd.ms-fontobject
        image/svg+xml;
    
    # Proxy all requests to Next.js app
    location / {
        proxy_pass http://localhost:3456;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }
    
    # Handle static files efficiently
    location /_next/static/ {
        proxy_pass http://localhost:3456;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Handle images and other static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://localhost:3456;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    
    # Security: Hide nginx version
    server_tokens off;
    
    # Logs
    access_log /var/log/nginx/rabbitmq-scout.access.log;
    error_log /var/log/nginx/rabbitmq-scout.error.log;
}
EOF

# Enable nginx site
if [ ! -L $NGINX_ENABLED ]; then
    print_status "Enabling nginx site..."
    sudo ln -s $NGINX_CONFIG $NGINX_ENABLED
fi

# Test nginx configuration
print_status "Testing nginx configuration..."
if ! sudo nginx -t; then
    print_error "Nginx configuration test failed"
    exit 1
fi

# Reload nginx
print_status "Reloading nginx..."
sudo systemctl reload nginx

# Ensure nginx is running
sudo systemctl enable nginx
sudo systemctl start nginx

# Save PM2 configuration
pm2 save

# Setup PM2 startup
print_status "Setting up PM2 startup..."
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME

# Wait a moment for services to start
sleep 3

# Check services status
print_status "Checking deployment status..."

# Check if Next.js app is running
if pm2 show $APP_NAME > /dev/null 2>&1; then
    print_status "Next.js app is running"
else
    print_error "Next.js app failed to start"
    pm2 logs $APP_NAME --lines 20
    exit 1
fi

# Check if nginx is running
if sudo systemctl is-active --quiet nginx; then
    print_status "Nginx is running"
else
    print_error "Nginx is not running"
    exit 1
fi

# Check if port 3456 is open
if netstat -tuln | grep -q ':3456' 2>/dev/null || ss -tuln | grep -q ':3456' 2>/dev/null; then
    print_status "Next.js app is listening on port 3456"
else
    print_warning "Port 3456 might not be open"
fi

# Final success message
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Access Information:"
echo "🌐 Your RabbitScout Management UI: http://rabbitmq.localhost"
echo ""
echo "📊 Management Commands:"
echo "📈 View logs: pm2 logs $APP_NAME"
echo "🔄 Restart app: pm2 restart $APP_NAME"
echo "📊 Monitor: pm2 monit"
echo "🛑 Stop app: pm2 stop $APP_NAME"
echo ""
echo "🔍 Troubleshooting:"
echo "📊 Nginx logs: sudo tail -f /var/log/nginx/rabbitmq-scout.error.log"
echo "🔧 Test nginx: sudo nginx -t"
echo "🔄 Reload nginx: sudo systemctl reload nginx"
echo "📋 PM2 status: pm2 status"
echo ""

# Show recent logs
print_status "Recent application logs:"
pm2 logs $APP_NAME --lines 5 --nostream