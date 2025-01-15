#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Create necessary directories and log files
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/"{install,backend-api,backend-main,kiosk-server,external}.log
sudo touch "$LOG_DIR/"{backend-api,backend-main,kiosk-server,external}.error.log
sudo chown -R $USER:$USER "$LOG_DIR"
chmod 755 "$LOG_DIR"
chmod 644 "$LOG_DIR"/*.log

mkdir -p "$MAIN_DIR"

# Logger function (defined first so it's available throughout the script)
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_DIR/install.log"
}

# Error handling
set -e  # Exit on error
set -x  # Print commands

# 1. Initial RPi4 Setup
log "🔧 Configuring Raspberry Pi..."

# Enable SPI and Serial if not already enabled
log "Enabling SPI and Serial interfaces..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
fi

if ! grep -q "^enable_uart=1" /boot/config.txt; then
    echo "enable_uart=1" | sudo tee -a /boot/config.txt
fi

# 2. System Setup 
log "📦 Installing system dependencies..."
sudo apt update && sudo apt install -y \
    build-essential \
    git \
    curl \
    wget \
    xterm \
    chromium-browser \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libssl-dev \
    libffi-dev \
    libudev-dev \
    x11-xserver-utils \
    setserial \
    unclutter \
    ca-certificates \
    openssl

# Verify system dependencies
log "Verifying system dependencies..."
for cmd in xrandr chromium-browser npm node python3 git curl wget; do
    if ! command -v $cmd &> /dev/null; then
        log "❌ Required command $cmd not found"
        exit 1
    fi
done

# GitHub CLI setup
log "🔑 Setting up GitHub CLI..."
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh -y
fi

# Install Node.js and npm if not already installed
log "📦 Installing Node.js and npm..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# Interactive GitHub authentication with validation
log "🔑 GitHub Authentication..."
while ! gh auth status &>/dev/null; do
    log "Please authenticate with GitHub. Choose 'HTTPS' and 'Paste an authentication token'"
    gh auth login
    if [ $? -ne 0 ]; then
        log "Authentication failed. Retrying..."
        sleep 2
    fi
done
log "✅ GitHub authentication successful"

# Clone repositories with validation
log "📥 Cloning repositories..."
cd "$MAIN_DIR"

clone_or_update_repo() {
    local repo=$1
    local dir=$2
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if [ ! -d "$dir" ]; then
            if gh repo clone "nqub/$repo" "$dir"; then
                log "✅ Successfully cloned $repo"
                return 0
            fi
        else
            cd "$dir"
            if git pull; then
                log "✅ Successfully updated $repo"
                cd ..
                return 0
            fi
            cd ..
        fi
        
        log "⚠️ Attempt $attempt failed for $repo. Retrying..."
        ((attempt++))
        sleep 2
    done
    
    log "❌ Failed to clone/update $repo after $max_attempts attempts"
    return 1
}

# Clone repositories
clone_or_update_repo "nqub-coin-dispenser" "backend"
clone_or_update_repo "token-dispenser-kiosk" "kiosk"
clone_or_update_repo "nqub-coin-dispenser-external-screen" "external"

# Setup Python Environment
log "🐍 Setting up Python environment..."
cd "$MAIN_DIR/backend"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install project requirements
log "📦 Installing Python requirements..."
pip install -r requirements.txt

# Generate Prisma client
log "🗄️ Generating Prisma client..."
prisma generate
prisma db push

# Setup frontend applications
log "🖥️ Setting up frontend applications..."
cd "$MAIN_DIR/kiosk"
npm install
npm run build

cd "$MAIN_DIR/external"
npm install

# Create Service Files
log "🔧 Creating systemd services..."

# Backend API service
sudo tee /etc/systemd/system/nqub-backend-api.service << EOF
[Unit]
Description=NQUB Backend API Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/backend
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
Environment="PATH=$PATH:/usr/local/bin"
ExecStart=/bin/bash -c 'source $VENV_DIR/bin/activate && python api_server.py'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/backend-api.log
StandardError=append:$LOG_DIR/backend-api.error.log
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Backend main service
sudo tee /etc/systemd/system/nqub-backend-main.service << EOF
[Unit]
Description=NQUB Backend Main Service
After=network.target nqub-backend-api.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/backend
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
Environment="PATH=$PATH:/usr/local/bin"
ExecStart=/bin/bash -c 'source $VENV_DIR/bin/activate  && python main.py'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/backend-main.log
StandardError=append:$LOG_DIR/backend-main.error.log
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Kiosk server service
sudo tee /etc/systemd/system/nqub-kiosk-server.service << EOF
[Unit]
Description=NQUB Kiosk Server
After=network.target nqub-backend-api.service nqub-backend-main.service
Requires=nqub-backend-api.service nqub-backend-main.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/kiosk
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/kiosk-server.log
StandardError=append:$LOG_DIR/kiosk-server.error.log
TimeoutStopSec=10
KillMode=mixed
ExecStop=/usr/bin/pkill -f "node.*kiosk"

[Install]
WantedBy=multi-user.target
EOF

# External display service
sudo tee /etc/systemd/system/nqub-external.service << EOF
[Unit]
Description=NQUB External Display
After=network.target nqub-backend-main.service
Requires=nqub-backend-main.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/external
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/external.log
StandardError=append:$LOG_DIR/external.error.log
TimeoutStopSec=10
KillMode=mixed
ExecStop=/usr/bin/pkill -f "node.*external"

[Install]
WantedBy=multi-user.target
EOF

# Configure Display Management
log "🖥️ Setting up display configuration..."
sudo tee /usr/local/bin/setup-displays << 'EOF'
#!/bin/bash
sleep 5  # Wait for X server

# Kill any existing unclutter processes
pkill -f unclutter || true

# Wait for X server to be fully ready
MAX_ATTEMPTS=30
ATTEMPTS=0
while ! xrandr --current > /dev/null 2>&1; do
    sleep 1
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
        echo "Failed to detect X server after $MAX_ATTEMPTS attempts"
        exit 1
    fi
done

# Get available outputs
OUTPUTS=$(xrandr --current | grep " connected" | cut -d" " -f1)

if [ -z "$OUTPUTS" ]; then
    echo "No displays detected"
    exit 1
fi

# Configure first available output as primary
PRIMARY=$(echo "$OUTPUTS" | head -n 1)
if [ -n "$PRIMARY" ]; then
    xrandr --output "$PRIMARY" --primary --mode 1920x1080 --pos 0x0
fi

# Configure second output if available
SECONDARY=$(echo "$OUTPUTS" | sed -n '2p')
if [ -n "$SECONDARY" ]; then
    xrandr --output "$SECONDARY" --mode 1920x1080 --pos 1920x0
fi

# Start unclutter with proper process management
unclutter -idle 0.1 -root &

# Launch Chrome for kiosk and external display
sleep 10  # Wait for displays to be properly configured

# Kill any existing Chrome instances
pkill -f chromium-browser || true

# Launch kiosk on primary display
DISPLAY=:0 chromium-browser --kiosk --no-first-run --noerrdialogs --disable-infobars \
    --disable-features=TranslateUI --disable-plugins --window-position=0,0 \
    --window-size=1920,1080 --start-fullscreen 'http://localhost:3000' &

# Launch external display on secondary display (if available)
if [ -n "$SECONDARY" ]; then
    DISPLAY=:0 chromium-browser --kiosk --no-first-run --noerrdialogs --disable-infobars \
        --disable-features=TranslateUI --disable-plugins --window-position=1920,0 \
        --window-size=1920,1080 --start-fullscreen 'http://localhost:5173' &
fi
EOF

sudo chmod +x /usr/local/bin/setup-displays

# Add to X server startup
sudo tee -a /etc/X11/xinit/xinitrc << 'EOF'
#!/bin/bash
/usr/local/bin/setup-displays
EOF

# Configure X server to start on boot
sudo raspi-config nonint do_boot_behaviour B4

# Service startup with proper order and validation
log "🚀 Starting services..."
sudo systemctl daemon-reload

# Start and verify each service in order
start_service() {
    local service=$1
    log "Starting $service..."
    
    # Check if dependent services are running
    for dep in $(systemctl show -p Requires,Wants $service | cut -d= -f2); do
        if [ "$dep" != "-.mount" ]; then
            while ! systemctl is-active $dep >/dev/null 2>&1; do
                log "⚠️ Required dependency $dep is not running. Waiting..."
                sleep 2
            done
        fi
    done
    
    sudo systemctl enable $service
    sudo systemctl start $service
    sleep 5
    if sudo systemctl is-active $service >/dev/null 2>&1; then
        log "✅ $service started successfully"
    else
        log "❌ Failed to start $service"
        log "Check logs with: sudo journalctl -u $service"
        return 1
    fi
}

# Start services in correct order
services=("nqub-backend-api" "nqub-backend-main" "nqub-kiosk-server" "nqub-external")
for service in "${services[@]}"; do
    start_service $service || exit 1
done

log "✅ Installation complete!"
log "📝 Log files are available in $LOG_DIR"
log "📊 Check individual service status with:"
log "sudo journalctl -u nqub-backend-api"
log "sudo journalctl -u nqub-backend-main"
log "sudo journalctl -u nqub-kiosk-server"
log "sudo journalctl -u nqub-external"

log "🔄 Please reboot the system to complete the installation:"

log "sudo reboot"