#!/bin/bash

# Initial setup script for Next.js + Nginx + RabbitMQ deployment
set -e

echo "🔧 Setting up environment for Next.js deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Update system packages
print_status "Updating system packages..."
sudo apt update

# Install Node.js and npm if not installed
if ! command -v node &> /dev/null; then
    print_status "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Install Yarn if not installed
if ! command -v yarn &> /dev/null; then
    print_status "Installing Yarn..."
    npm install -g yarn
fi

# Install PM2 if not installed
if ! command -v pm2 &> /dev/null; then
    print_status "Installing PM2..."
    npm install -g pm2
fi

# Install Nginx if not installed
if ! command -v nginx &> /dev/null; then
    print_status "Installing Nginx..."
    sudo apt install -y nginx
fi

# Install RabbitMQ if not installed
if ! command -v rabbitmq-server &> /dev/null; then
    print_status "Installing RabbitMQ..."
    sudo apt install -y rabbitmq-server
    
    # Enable RabbitMQ management plugin
    sudo rabbitmq-plugins enable rabbitmq_management
    
    # Start and enable RabbitMQ
    sudo systemctl start rabbitmq-server
    sudo systemctl enable rabbitmq-server
fi

# Create necessary directories
print_status "Creating necessary directories..."
sudo mkdir -p /var/www
sudo chown -R $USER:$USER /var/www

# Set up firewall (optional)
print_warning "Setting up firewall rules..."
sudo ufw allow 'Nginx Full' || true
sudo ufw allow 22 || true
sudo ufw allow 15672 || true  # RabbitMQ management
sudo ufw allow 3456 || true   # Next.js app port

# Create environment template if it doesn't exist
if [ ! -f ".env.example" ]; then
    print_status "Creating environment template..."
    cat > .env.example << 'EOF'
# Port Configuration
PORT=3456

# RabbitMQ Configuration (Public)
NEXT_PUBLIC_RABBITMQ_HOST=localhost
NEXT_PUBLIC_RABBITMQ_PORT=15672
NEXT_PUBLIC_RABBITMQ_VHOST=/

# RabbitMQ Credentials (Private)
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
EOF
fi

# Create .env.local and .env.production from template
if [ ! -f ".env.local" ]; then
    print_status "Creating .env.local..."
    cp .env.example .env.local
fi

if [ ! -f ".env.production" ]; then
    print_status "Creating .env.production..."
    cp .env.example .env.production
fi

# Update .gitignore
print_status "Updating .gitignore..."
cat >> .gitignore << 'EOF'

# Environment variables
.env.local
.env.production
.env.development.local
.env.test.local
.env.production.local

# PM2 logs
logs/
EOF

# Create next.config.js if it doesn't exist
if [ ! -f "next.config.js" ]; then
    print_status "Creating next.config.js..."
    cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  experimental: {
    serverActions: {
      bodySizeLimit: '2mb',
    },
  },
  env: {
    RABBITMQ_USERNAME: process.env.RABBITMQ_USERNAME,
    RABBITMQ_PASSWORD: process.env.RABBITMQ_PASSWORD,
  }
}

module.exports = nextConfig
EOF
fi

# Make deploy script executable
if [ -f "deploy.sh" ]; then
    chmod +x deploy.sh
    print_status "Made deploy.sh executable"
fi

# Check services
print_status "Checking services..."

# Check Nginx
if sudo systemctl is-active --quiet nginx; then
    print_status "Nginx is running"
else
    print_warning "Starting Nginx..."
    sudo systemctl start nginx
    sudo systemctl enable nginx
fi

# Check RabbitMQ
if sudo systemctl is-active --quiet rabbitmq-server; then
    print_status "RabbitMQ is running"
else
    print_warning "Starting RabbitMQ..."
    sudo systemctl start rabbitmq-server
    sudo systemctl enable rabbitmq-server
fi

# Display versions
echo ""
echo "📋 Installed Versions:"
echo "🟢 Node.js: $(node --version)"
echo "🟢 Yarn: $(yarn --version)"
echo "🟢 PM2: $(pm2 --version)"
echo "🟢 Nginx: $(nginx -v 2>&1)"
echo ""

print_status "Setup completed successfully!"
echo ""
echo "📝 Next Steps:"
echo "1. Edit .env.local and .env.production with your actual values"
echo "2. Run: yarn install"
echo "3. Test your app: yarn dev"
echo "4. Deploy: ./deploy.sh"
echo ""
echo "🔍 Useful URLs:"
echo "🌐 RabbitMQ Management: http://localhost:15672 (guest/guest)"
echo "🐰 Your app will be at: http://localhost (after deployment)"