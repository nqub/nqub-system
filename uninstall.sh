#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
BACKUP_DIR="$HOME/nqub-backup"
LOG_DIR="/var/log/nqub"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "🔍 Starting cleanup process..."

# Function to ask yes/no questions
ask() {
    local prompt=$1
    local answer
    while true; do
        read -p "$prompt (y/n): " answer
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Stop services
if ask "Stop all NQUB services?"; then
    log "🛑 Stopping services..."
    services=(nqub-backend-api nqub-backend-main nqub-kiosk-server nqub-external)
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            sudo systemctl stop $service
            log "Stopped $service"
        fi
        if systemctl is-enabled --quiet $service; then
            sudo systemctl disable $service
            log "Disabled $service"
        fi
    done
fi

# Remove service files
if ask "Remove service files?"; then
    log "🗑️ Removing service files..."
    sudo rm -f /etc/systemd/system/nqub-*.service
    sudo systemctl daemon-reload
    log "✅ Removed service files and reloaded daemon"
fi

# Handle logs
if ask "Remove all logs?"; then
    log "🗑️ Removing logs..."
    sudo rm -rf "$LOG_DIR"
    log "✅ Removed logs directory"
else
    log "📝 Keeping logs in $LOG_DIR"
fi

# Handle application files and Prisma data
if ask "Remove all application files (including Prisma data)?"; then
    log "🗑️ Removing all application files..."
    rm -rf "$MAIN_DIR"
    log "✅ Removed all application files"
else
    if ask "Remove application files but keep Prisma data?"; then
        log "💾 Backing up Prisma data..."
        if [ -d "$MAIN_DIR/backend/prisma" ]; then
            mkdir -p "$BACKUP_DIR"
            cp -r "$MAIN_DIR/backend/prisma" "$BACKUP_DIR/"
            rm -rf "$MAIN_DIR"
            log "✅ Removed application files"
            log "✅ Prisma data backed up to $BACKUP_DIR/prisma/"
        else
            log "❌ Prisma directory not found"
        fi
    fi
fi

# Handle Node.js and GitHub CLI
if ask "Remove Node.js and GitHub CLI?"; then
    log "🗑️ Removing Node.js and GitHub CLI..."
    sudo apt remove -y nodejs npm gh
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /etc/apt/sources.list.d/github-cli.list
    sudo rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo apt autoremove -y
    log "✅ Removed Node.js and GitHub CLI"
fi

# Handle system dependencies
if ask "Remove system dependencies? (This might affect other applications)"; then
    log "🗑️ Removing system dependencies..."
    sudo apt remove -y \
        build-essential \
        git \
        curl \
        wget \
        xterm \
        chromium-browser \
        python3-pip \
        python3-venv \
        python3-dev \
        libssl-dev \
        libffi-dev \
        libudev-dev \
        x11-xserver-utils \
        setserial \
        unclutter
    sudo apt autoremove -y
    sudo apt clean
    log "✅ Removed system dependencies"
fi

# Remove device configurations
if ask "Remove device configurations (SPI, UART, USB rules)?"; then
    log "🔧 Removing device configurations..."
    # Remove USB rules
    sudo rm -f /etc/udev/rules.d/99-usb-serial.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    # Remove SPI and UART config
    sudo sed -i '/^dtparam=spi=on/d' /boot/config.txt
    sudo sed -i '/^enable_uart=1/d' /boot/config.txt
    log "✅ Removed device configurations"
fi

# Clean caches
if ask "Clean npm and pip caches?"; then
    log "🧹 Cleaning caches..."
    npm cache clean --force
    pip cache purge
    log "✅ Cleaned npm and pip caches"
fi

log "✅ Cleanup complete!"
log "⚠️ Note: Some configuration files in your home directory may still remain"
if [ -d "$BACKUP_DIR" ]; then
    log "💾 Your data backup is located at: $BACKUP_DIR"
fi
log "🔄 Please reboot your system to complete the uninstallation:"
log "sudo reboot"