#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    # Also log to a main install log file
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_DIR/install.log"
}

# Error handling without trap
set -e  # Still exit on error
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
log "📦 Setting up system directories..."
# Create necessary directories and log files
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/"{install,backend-api,backend-main,kiosk,external}.log
sudo touch "$LOG_DIR/"{backend-api,backend-main,kiosk,external}.error.log
sudo chown -R $USER:$USER "$LOG_DIR"
chmod 755 "$LOG_DIR"
chmod 644 "$LOG_DIR"/*.log

mkdir -p "$MAIN_DIR"

# Install system dependencies
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

## GitHub CLI setup
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

# Actually clone the repositories
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

# Setup frontend applications
log "🖥️ Setting up frontend applications..."
cd "$MAIN_DIR/kiosk"
npm install
npm run build

cd "$MAIN_DIR/external"
npm install
npm run build

# Configure Display Management
log "🖥️ Setting up display configuration..."
sudo tee /usr/local/bin/setup-displays << EOF
#!/bin/bash
sleep 5  # Wait for X server
xrandr --output HDMI-1 --primary --mode 1920x1080 --pos 0x0
xrandr --output HDMI-2 --mode 1920x1080 --pos 1920x0
unclutter -idle 0.1 -root &  # Hide mouse cursor
EOF

sudo chmod +x /usr/local/bin/setup-displays

# Add to X server startup
sudo tee -a /etc/X11/xinit/xinitrc << EOF
/usr/local/bin/setup-displays
EOF

# Configure X server to start on boot
sudo raspi-config nonint do_boot_behaviour B4

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

[Install]
WantedBy=multi-user.target
EOF

# Backend main service
sudo tee /etc/systemd/system/nqub-backend-main.service << EOF
[Unit]
Description=NQUB Backend Main Service
After=nqub-backend-api.service
Requires=nqub-backend-api.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/backend
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
Environment="PATH=$PATH:/usr/local/bin"
ExecStart=/bin/bash -c 'source $VENV_DIR/bin/activate && python main.py'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/backend-main.log
StandardError=append:$LOG_DIR/backend-main.error.log

[Install]
WantedBy=multi-user.target
EOF

# Kiosk service with dependency and health check
sudo tee /etc/systemd/system/nqub-kiosk.service << EOF
[Unit]
Description=NQUB Kiosk Interface
After=graphical.target nqub-backend-api.service nqub-backend-main.service
Requires=nqub-backend-api.service nqub-backend-main.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/kiosk
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
ExecStartPre=/usr/local/bin/setup-displays
ExecStart=/usr/bin/chromium-browser --kiosk --disable-restore-session-state --window-position=0,0 --noerrdialogs --disable-infobars --no-first-run --disable-features=TranslateUI --disable-session-crashed-bubble http://localhost:3000
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/kiosk.log
StandardError=append:$LOG_DIR/kiosk.error.log

[Install]
WantedBy=graphical.target
EOF

# External display service with dependency
sudo tee /etc/systemd/system/nqub-external.service << EOF
[Unit]
Description=NQUB External Display
After=graphical.target nqub-backend-api.service nqub-backend-main.service
Requires=nqub-backend-api.service nqub-backend-main.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/external
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
ExecStart=/usr/bin/chromium-browser --kiosk --disable-restore-session-state --window-position=1920,0 --noerrdialogs --disable-infobars --no-first-run --disable-features=TranslateUI --disable-session-crashed-bubble http://localhost:5173
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/external.log
StandardError=append:$LOG_DIR/external.error.log

[Install]
WantedBy=graphical.target
EOF

# Start npm servers
log "🚀 Starting npm servers..."
cd "$MAIN_DIR/kiosk"
npm run preview -- --port 3000 --host &
cd "$MAIN_DIR/external"
npm run preview -- --port 5173 --host &

# Service startup with proper order and validation
log "🚀 Starting services..."
sudo systemctl daemon-reload

# Start and verify each service in order
start_service() {
    local service=$1
    log "Starting $service..."
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
services=("nqub-backend-api" "nqub-backend-main" "nqub-kiosk" "nqub-external")
for service in "${services[@]}"; do
    start_service $service || exit 1
done

log "✅ Installation complete!"
log "📝 Log files are available in $LOG_DIR"
log "📊 Check individual service status with:"
log "sudo systemctl status nqub-backend-api"
log "sudo systemctl status nqub-backend-main"
log "sudo systemctl status nqub-kiosk"
log "sudo systemctl status nqub-external"

log "🔄 Please reboot the system to complete the installation:"
log "sudo reboot"