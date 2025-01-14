#!/bin/bash

# Configuration (matching install.sh)
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Stop and disable services
log "🛑 Stopping and disabling services..."
sudo systemctl stop nqub-backend nqub-backend-main nqub-kiosk nqub-external
sudo systemctl disable nqub-backend nqub-backend-main nqub-kiosk nqub-external

# Remove service files
log "🗑️ Removing systemd service files..."
sudo rm -f /etc/systemd/system/nqub-backend.service
sudo rm -f /etc/systemd/system/nqub-backend-main.service
sudo rm -f /etc/systemd/system/nqub-kiosk.service
sudo rm -f /etc/systemd/system/nqub-external.service
sudo systemctl daemon-reload

# Remove display configuration
log "🗑️ Removing display configuration..."
sudo rm -f /usr/local/bin/setup-displays

# Remove autostart configuration
log "🗑️ Removing autostart configuration..."
rm -rf $HOME/.config/lxsession/LXDE-pi/autostart

# Remove main directory and all project files
log "🗑️ Removing project directories..."
rm -rf "$MAIN_DIR"

# Remove logs
log "🗑️ Removing log files..."
sudo rm -rf "$LOG_DIR"

# Clean up GitHub CLI (optional)
log "🗑️ Removing GitHub CLI..."
sudo apt remove -y gh
sudo rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
sudo rm -f /etc/apt/sources.list.d/github-cli.list

# Optional: Remove Node.js
read -p "Do you want to remove Node.js? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log "🗑️ Removing Node.js..."
    sudo apt remove -y nodejs
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /etc/apt/sources.list.d/nodesource.list.save
fi

# Optional: Remove Python virtual environment packages
read -p "Do you want to remove Python development packages? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log "🗑️ Removing Python development packages..."
    sudo apt remove -y python3-venv python3-pip python3-dev
fi

log "✅ Uninstallation complete!"
log "Note: System-wide dependencies like build-essential, git, etc. were not removed."
log "If you want to remove them, you can do so manually using 'sudo apt remove'."