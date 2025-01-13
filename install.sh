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
clone_or_update_repo "token-dis-kiosk" "kiosk"
clone_or_update_repo "nqub-coin-dispenser-external-screen" "external"

# Install SSL and Python dependencies first
log "🔒 Setting up SSL and Python dependencies..."
sudo apt-get update
sudo apt-get install -y \
    python3-dev \
    libssl-dev \
    libffi-dev \
    build-essential \
    python3-pip \
    python3-venv \
    ca-certificates \
    openssl \
    wget

# Fix SSL certificates
log "🔒 Updating SSL certificates..."
sudo update-ca-certificates --fresh

# Download pip manually with wget
log "📦 Downloading pip..."
wget --no-check-certificate https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --trusted-host pypi.org --trusted-host files.pythonhosted.org

# Create and configure pip.conf with more detailed settings
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
no-cache-dir = true
index-url = http://pypi.org/simple/
extra-index-url = https://www.piwheels.org/simple/
EOF

# Setup Python virtual environment
log "🐍 Setting up Python environment..."
cd "$MAIN_DIR/backend"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install base packages with retries and proper SSL handling
log "📦 Installing base Python packages..."
for package in pip setuptools wheel; do
    for i in {1..3}; do
        if python3 -m pip install --upgrade $package \
            --no-cache-dir \
            --trusted-host pypi.org \
            --trusted-host files.pythonhosted.org \
            --trusted-host piwheels.org; then
            log "✅ Installed $package successfully"
            break
        else
            log "⚠️ Attempt $i for $package failed, retrying..."
            sleep 5
        fi
    done
done

# Install project requirements with proper error handling
log "📦 Installing project requirements..."
for i in {1..3}; do
    if pip install -r requirements.txt \
        --no-cache-dir \
        --trusted-host pypi.org \
        --trusted-host files.pythonhosted.org \
        --trusted-host piwheels.org; then
        log "✅ Project requirements installed successfully"
        break
    else
        log "⚠️ Attempt $i failed, retrying..."
        sleep 5
    fi
done