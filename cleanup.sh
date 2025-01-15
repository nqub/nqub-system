#!/bin/bash

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

# Always stop services first for safety
if ask "Stop all NQUB services?"; then
    log "🛑 Stopping services..."
    sudo systemctl stop nqub-backend-api nqub-backend-main nqub-kiosk-server nqub-external
    sudo systemctl disable nqub-backend-api nqub-backend-main nqub-kiosk-server nqub-external
fi

# Remove service files
if ask "Remove service files?"; then
    log "🗑️ Removing service files..."
    sudo rm -f /etc/systemd/system/nqub-*.service
    sudo systemctl daemon-reload
fi

# Handle logs
if ask "Remove all logs?"; then
    log "🗑️ Removing logs..."
    sudo rm -rf /var/log/nqub
else
    log "📝 Keeping logs..."
fi

# Handle application files and Prisma data
if ask "Remove all application files (including Prisma data)?"; then
    log "🗑️ Removing all application files..."
    rm -rf ~/nqub-system
else
    if ask "Remove application files but keep Prisma data?"; then
        log "💾 Backing up Prisma data..."
        if [ -d ~/nqub-system/backend/prisma ]; then
            mkdir -p ~/nqub-backup
            cp -r ~/nqub-system/backend/prisma ~/nqub-backup/
        fi
        log "🗑️ Removing application files..."
        rm -rf ~/nqub-system
        log "✅ Prisma data backed up to ~/nqub-backup/prisma/"
    fi
fi

# Handle Node.js and GitHub CLI
if ask "Remove Node.js and GitHub CLI?"; then
    log "🗑️ Removing Node.js and GitHub CLI..."
    sudo apt remove -y nodejs gh
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /etc/apt/sources.list.d/github-cli.list
    sudo rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
fi

log "✅ Cleanup complete!"