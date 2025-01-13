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

# Create a directory for downloaded packages
DOWNLOAD_DIR="$HOME/pip-packages"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Download pip first using curl
echo "📥 Downloading pip..."
curl -k http://pypi.org/pypi/pip/json | grep download_url | grep whl | head -n1 | cut -d'"' -f4 | xargs curl -k -O
PIP_WHL=$(ls *.whl)

# Install pip from downloaded file
echo "📦 Installing pip from local file..."
python3 -m pip install --no-index --find-links=. $PIP_WHL

# Define package list
declare -A PACKAGES=(
    ["pip"]="24.0"
    ["pyserial"]="3.5"
    ["prisma"]="0.11.0"
    ["flask"]="3.0.2"
    ["flask-cors"]="4.0.0"
    ["requests"]="2.31.0"
)

# Download and install each package
for package in "${!PACKAGES[@]}"; do
    version="${PACKAGES[$package]}"
    echo "📥 Downloading $package==$version..."
    
    # Try multiple methods to download the package
    if ! curl -k -L -o "$package-$version.whl" "http://files.pythonhosted.org/packages/py3/$package/$version/$package-$version-py3-none-any.whl"; then
        if ! curl -k -L -o "$package-$version.tar.gz" "http://pypi.org/packages/source/${package:0:1}/$package/$package-$version.tar.gz"; then
            echo "⚠️ Failed to download $package"
            continue
        fi
    fi
    
    echo "📦 Installing $package locally..."
    PYTHONHTTPSVERIFY=0 pip install --no-index --find-links=. ./$package-$version.* || true
done

# Clean up downloads
cd -
rm -rf "$DOWNLOAD_DIR"

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