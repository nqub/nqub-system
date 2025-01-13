#!/bin/bash

# Exit on error, print commands
set -e
set -x

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Error handling
handle_error() {
    local line_no=$1
    local error_code=$2
    echo "❌ Error occurred at line $line_no (Exit code: $error_code)"
    echo "Please check the logs for more details"
    exit 1
}
trap 'handle_error $LINENO $?' ERR

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 1. Initial RPi4 Setup
log "🔧 Configuring Raspberry Pi..."
sudo raspi-config nonint do_spi 0  # Enable SPI
sudo raspi-config nonint do_serial 0  # Enable Serial Port
sudo raspi-config nonint do_expand_rootfs  # Expand filesystem

# 2. System Setup
log "📦 Setting up system directories..."
sudo mkdir -p "$LOG_DIR"
sudo chown $USER:$USER "$LOG_DIR"
mkdir -p "$MAIN_DIR"
cd "$MAIN_DIR"

# Install system dependencies
log "🔧 Installing system dependencies..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y \
    build-essential \
    git \
    curl \
    xterm \
    chromium-browser \
    python3 \
    python3-pip \
    python3-venv \
    x11-xserver-utils \
    setserial \
    libssl-dev \
    libffi-dev \
    python3-dev \
    libudev-dev \
    unclutter

# Install Node.js 20.x
log "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install GitHub CLI and authenticate
log "🔑 Setting up GitHub CLI..."
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh -y
fi

log "🔑 Please authenticate with GitHub..."
gh auth login

# 3. Clone Repositories
log "📥 Cloning repositories..."
cd "$MAIN_DIR"

clone_or_update_repo() {
    local repo=$1
    local dir=$2
    if [ ! -d "$dir" ]; then
        gh repo clone "nqub/$repo" "$dir"
    else
        cd "$dir"
        git pull
        cd ..
    fi
}

clone_or_update_repo "nqub-coin-dispenser" "backend"
clone_or_update_repo "token-dispenser-kiosk" "kiosk"
clone_or_update_repo "nqub-coin-dispenser-external-screen" "external"

# Fix SSL certificates
log "🔒 Updating SSL certificates..."
sudo apt-get install -y ca-certificates openssl
sudo update-ca-certificates --fresh

# Create and configure pip.conf
log "⚙️ Configuring pip..."
mkdir -p $HOME/.pip
cat > $HOME/.pip/pip.conf << EOF
[global]
trusted-host = 
    pypi.org
    files.pythonhosted.org
    pypi.python.org
    piwheels.org
timeout = 60
retries = 3
EOF

# Setup Python virtual environment with proper SSL
log "🐍 Setting up Python environment..."
cd "$MAIN_DIR/backend"

# Install SSL dependencies first
sudo apt-get install -y \
    python3-dev \
    libssl-dev \
    libffi-dev \
    build-essential \
    python3-pip

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Upgrade pip with special flags
python3 -m pip install --no-cache-dir --upgrade pip \
    --trusted-host pypi.org \
    --trusted-host files.pythonhosted.org \
    --trusted-host piwheels.org

# Install wheel and setuptools first
pip install --no-cache-dir wheel setuptools \
    --trusted-host pypi.org \
    --trusted-host files.pythonhosted.org \
    --trusted-host piwheels.org

# Install requirements with retry mechanism
log "📦 Installing Python packages..."
for i in {1..3}; do
    if pip install -r requirements.txt \
        --no-cache-dir \
        --trusted-host pypi.org \
        --trusted-host files.pythonhosted.org \
        --trusted-host piwheels.org; then
        log "✅ Python packages installed successfully"
        break
    else
        log "⚠️ Attempt $i failed, retrying..."
        sleep 5
    fi
done

# Initialize database
log "🗄️ Initializing database..."
prisma db push

# 5. Setup Frontend Applications
log "🖥️ Setting up frontend applications..."

# Kiosk setup
cd "$MAIN_DIR/kiosk"
npm install
npm run build

# External display setup
cd "$MAIN_DIR/external"
npm install
npm run build

# 6. Configure Display Management
log "🖥️ Setting up display configuration..."
sudo tee /usr/local/bin/setup-displays << EOF
#!/bin/bash
sleep 5  # Wait for X server
xrandr --output HDMI-1 --primary --mode 1920x1080 --pos 0x0
xrandr --output HDMI-2 --mode 1920x1080 --pos 1920x0
unclutter -idle 0.1 -root &  # Hide mouse cursor
EOF

sudo chmod +x /usr/local/bin/setup-displays

# 7. Create Service Files
log "🔧 Creating systemd services..."

# Backend service
sudo tee /etc/systemd/system/nqub-backend.service << EOF
[Unit]
Description=NQUB Backend Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/backend
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"
Environment="PATH=$PATH:/usr/local/bin"
ExecStart=/bin/bash -c 'source $VENV_DIR/bin/activate && python api_server.py & python main.py'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/backend.log
StandardError=append:$LOG_DIR/backend.error.log

[Install]
WantedBy=multi-user.target
EOF

# Kiosk service
sudo tee /etc/systemd/system/nqub-kiosk.service << EOF
[Unit]
Description=NQUB Kiosk Interface
After=graphical.target

[Service]
Type=simple
User=$USER
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

# External display service
sudo tee /etc/systemd/system/nqub-external.service << EOF
[Unit]
Description=NQUB External Display
After=graphical.target

[Service]
Type=simple
User=$USER
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

# 8. Configure Autostart
mkdir -p $HOME/.config/lxsession/LXDE-pi
cat > $HOME/.config/lxsession/LXDE-pi/autostart << EOF
@xset s off
@xset -dpms
@xset s noblank
EOF

# 9. Start Services
log "🚀 Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable nqub-backend nqub-kiosk nqub-external
sudo systemctl start nqub-backend nqub-kiosk nqub-external

log "✅ Installation complete!"
log "📝 Log files are available in $LOG_DIR"
log "📊 Check service status with: sudo systemctl status nqub-[backend|kiosk|external]"