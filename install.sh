#!/bin/bash

# Exit on error, print commands
set -e
set -x

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"

# Error handling with more detail
handle_error() {
    local line_no=$1
    local error_code=$2
    echo "❌ Error occurred at line $line_no (Exit code: $error_code)"
    echo "Please check the logs for more details"
    exit 1
}
trap 'handle_error $LINENO $?' ERR

# Create main directory and log directory
mkdir -p "$MAIN_DIR"
sudo mkdir -p "$LOG_DIR"
sudo chown $USER:$USER "$LOG_DIR"
cd "$MAIN_DIR"

# 1. Enhanced System Prerequisites
echo "📦 Installing system prerequisites..."
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
sudo apt full-upgrade -y

# SSL/Security packages
echo "🔒 Setting up SSL/Security..."
sudo apt install -y ca-certificates openssl libssl-dev libffi-dev python3-dev
sudo update-ca-certificates --fresh

# Time synchronization
echo "⏰ Synchronizing system time..."
sudo apt install -y ntp ntpdate
sudo systemctl stop ntp
sudo ntpdate -u pool.ntp.org
sudo systemctl start ntp
sleep 5

# Core development packages
sudo apt install -y build-essential git xterm setserial x11-xserver-utils chromium-browser python3 python3-pip python3-venv python3-wheel python3-setuptools

# Install Github CLI
echo "🔧 Installing GitHub CLI..."
type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

# GitHub Authentication
echo "🔑 Please authenticate with GitHub..."
gh auth login

# Install Node.js 20.x
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# 2. Detect Displays
echo "🖥️ Detecting displays..."
if command -v xrandr &> /dev/null; then
    PRIMARY_DISPLAY=$(xrandr | grep " connected" | head -n 1 | cut -d' ' -f1)
    SECONDARY_DISPLAY=$(xrandr | grep " connected" | tail -n 1 | cut -d' ' -f1)
    echo "Primary display: $PRIMARY_DISPLAY"
    echo "Secondary display: $SECONDARY_DISPLAY"
else
    echo "xrandr not available, using default display configuration"
    PRIMARY_DISPLAY=HDMI-1
    SECONDARY_DISPLAY=HDMI-2
fi

# 3. Clone Repositories
echo "📥 Cloning repositories..."
[ ! -d "nqub-coin-dispenser" ] && gh repo clone nqub/nqub-coin-dispenser
[ ! -d "token-dispenser-kiosk" ] && gh repo clone nqub/token-dispenser-kiosk
[ ! -d "external-display" ] && gh repo clone nqub/nqub-coin-dispenser-external-screen external-display

# 4. Enhanced Python Backend Setup
echo "🐍 Setting up Python backend..."
cd "$MAIN_DIR/nqub-coin-dispenser"

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# Configure pip for offline/insecure installation
mkdir -p ~/.pip
cat > ~/.pip/pip.conf << EOF
[global]
timeout = 180
retries = 15
trusted-host = 
    pypi.org
    files.pythonhosted.org
    piwheels.org
    www.piwheels.org
EOF

# Upgrade pip with SSL verification disabled
echo "📦 Upgrading pip..."
python3 -m pip install --upgrade pip --trusted-host pypi.org --trusted-host files.pythonhosted.org

# Install packages with SSL verification disabled
echo "📦 Installing Python packages..."
PACKAGES=("pyserial" "prisma" "flask[async]" "flask-cors" "requests")

for package in "${PACKAGES[@]}"; do
    echo "Installing $package..."
    for i in {1..3}; do
        echo "Attempt $i of 3..."
        if pip install --no-cache-dir \
            --trusted-host pypi.org \
            --trusted-host files.pythonhosted.org \
            --trusted-host piwheels.org \
            --trusted-host www.piwheels.org \
            "$package"; then
            echo "Successfully installed $package"
            break
        elif [ $i -eq 3 ]; then
            echo "Failed to install $package after 3 attempts"
            exit 1
        else
            echo "Retrying in 5 seconds..."
            sleep 5
        fi
    done
done

# Initialize prisma with retry
echo "🔄 Initializing Prisma..."
prisma db push || (sleep 5 && prisma db push)

# 5. Setup Kiosk (Primary Screen)
echo "🖥️ Setting up kiosk application..."
cd "$MAIN_DIR/token-dispenser-kiosk"
npm install
npm run build

# 6. Setup External Display
echo "🖥️ Setting up external display application..."
cd "$MAIN_DIR/external-display"
npm install
npm run build

# 7. Create systemd services
echo "🔧 Creating systemd services..."

# Backend Service
sudo tee /etc/systemd/system/nqub-backend.service << EOF
[Unit]
Description=NQUB Backend Services
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MAIN_DIR/nqub-coin-dispenser
Environment="SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
ExecStart=/bin/bash -c 'source venv/bin/activate && python api_server.py & python main.py'
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/backend.log
StandardError=append:$LOG_DIR/backend.error.log

[Install]
WantedBy=multi-user.target
EOF

# Kiosk Service (Primary Screen)
sudo tee /etc/systemd/system/nqub-kiosk.service << EOF
[Unit]
Description=NQUB Kiosk Application
After=graphical.target

[Service]
Type=simple
User=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority
WorkingDirectory=$MAIN_DIR/token-dispenser-kiosk
ExecStart=/usr/bin/chromium-browser --kiosk --disable-restore-session-state --window-position=0,0 --no-sandbox http://localhost:3000
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/kiosk.log
StandardError=append:$LOG_DIR/kiosk.error.log

[Install]
WantedBy=graphical.target
EOF

# External Display Service
sudo tee /etc/systemd/system/nqub-external.service << EOF
[Unit]
Description=NQUB External Display
After=graphical.target

[Service]
Type=simple
User=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority
WorkingDirectory=$MAIN_DIR/external-display
ExecStart=/usr/bin/npm run preview
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/external.log
StandardError=append:$LOG_DIR/external.error.log

[Install]
WantedBy=graphical.target
EOF

# Screen configuration service
sudo tee /etc/systemd/system/nqub-screen-config.service << EOF
[Unit]
Description=NQUB Screen Configuration
After=graphical.target

[Service]
Type=oneshot
User=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority
ExecStart=/usr/bin/xrandr --output $PRIMARY_DISPLAY --primary --auto --output $SECONDARY_DISPLAY --auto --right-of $PRIMARY_DISPLAY
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

# 8. Create update script with enhanced error handling
cat > "$MAIN_DIR/update.sh" << 'EOF'
#!/bin/bash
set -e

cd "$HOME/nqub-system"

handle_error() {
    echo "❌ Error occurred during update at line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

# Update all repositories
for repo in */; do
    cd "$repo"
    echo "📦 Updating $(basename $repo)..."
    git pull
    if [ -f "package.json" ]; then
        npm install
        npm run build
    elif [ -f "requirements.txt" ]; then
        source venv/bin/activate
        pip install -r requirements.txt \
            --trusted-host pypi.org \
            --trusted-host files.pythonhosted.org \
            --trusted-host piwheels.org
        prisma db push
        deactivate
    fi
    cd ..
done

# Restart services
echo "🔄 Restarting services..."
sudo systemctl restart nqub-backend nqub-kiosk nqub-external

echo "✅ Update complete!"
EOF

chmod +x "$MAIN_DIR/update.sh"

# Enable and start services
echo "🔧 Enabling and starting services..."
sudo systemctl daemon-reload
sudo systemctl enable nqub-backend nqub-kiosk nqub-external nqub-screen-config
sudo systemctl start nqub-screen-config
sudo systemctl start nqub-backend nqub-kiosk nqub-external

echo "✅ Installation complete!"
echo "📝 Services are running and will start automatically on boot"
echo "🔄 To update all applications, run: $MAIN_DIR/update.sh"
echo "📊 View logs in: $LOG_DIR"
echo "🔍 Check service status with:"
echo "   sudo systemctl status nqub-backend"
echo "   sudo systemctl status nqub-kiosk"
echo "   sudo systemctl status nqub-external"

# Verify installation
echo "🔍 Verifying installation..."
if ! systemctl is-active --quiet nqub-backend; then
    echo "⚠️ Warning: Backend service is not running. Check logs at $LOG_DIR/backend.error.log"
fi
if ! systemctl is-active --quiet nqub-kiosk; then
    echo "⚠️ Warning: Kiosk service is not running. Check logs at $LOG_DIR/kiosk.error.log"
fi
if ! systemctl is-active --quiet nqub-external; then
    echo "⚠️ Warning: External display service is not running. Check logs at $LOG_DIR/external.error.log"
fi