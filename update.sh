#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_DIR/update.log"
}

# Error handling
set -e  # Exit on error

# Check if installation exists
if [ ! -d "$MAIN_DIR" ]; then
    log "❌ Installation directory not found. Please run install.sh first."
    exit 1
fi

# Stop services before update
log "🛑 Stopping services for update..."
services=("nqub-backend-api" "nqub-backend-main" "nqub-kiosk-server" "nqub-external")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        sudo systemctl stop $service
        log "✅ Stopped $service"
    fi
done

# Function to update repository
update_repo() {
    local dir=$1
    local name=$(basename $dir)
    
    log "🔄 Updating $name..."
    if [ -d "$dir" ]; then
        cd "$dir"
        # Stash any local changes
        git stash
        # Pull latest changes
        if git pull; then
            log "✅ Successfully updated $name"
            cd ..
            return 0
        else
            log "❌ Failed to update $name"
            cd ..
            return 1
        fi
    else
        log "❌ Directory $dir not found"
        return 1
    fi
}

# Update repositories
cd "$MAIN_DIR"
update_repo "backend" || exit 1
update_repo "kiosk" || exit 1
update_repo "external" || exit 1

# Update Python dependencies
log "📦 Updating Python dependencies..."
cd "$MAIN_DIR/backend"
source "$VENV_DIR/bin/activate"
pip install --upgrade -r requirements.txt

# Update Prisma client without affecting the database
log "🔄 Updating Prisma client..."
prisma generate

# Update Node.js dependencies for frontend applications
log "📦 Updating frontend dependencies..."
cd "$MAIN_DIR/kiosk"
npm install
npm run build

cd "$MAIN_DIR/external"
npm install

# Start services in correct order
log "🚀 Starting services..."
for service in "${services[@]}"; do
    sudo systemctl start $service
    sleep 5
    if sudo systemctl is-active $service >/dev/null 2>&1; then
        log "✅ $service started successfully"
    else
        log "❌ Failed to start $service"
        log "Check logs with: sudo journalctl -u $service"
        exit 1
    fi
done

log "✅ Update complete!"
log "📝 Log files are available in $LOG_DIR"
log "📊 Check individual service status with:"
for service in "${services[@]}"; do
    log "sudo journalctl -u $service"
done