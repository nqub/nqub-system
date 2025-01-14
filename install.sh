#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# error handling without trap
set -e  # Still exit on error
set -x  # Print commands

# 1. Initial RPi4 Setup
log "🔧 Configuring Raspberry Pi..."
# Use raspi-config for safe filesystem expansion
sudo raspi-config --expand-rootfs || {
    log "❌ Failed to expand filesystem"
    exit 1
}
sudo raspi-config nonint do_spi 0 || {
    log "❌ Failed to enable SPI"
    exit 1
}
sudo raspi-config nonint do_serial 0 || {
    log "❌ Failed to enable Serial Port"
    exit 1
}

# 2. System Setup (unchanged until GitHub part)
[Previous system setup parts remain the same until GitHub CLI setup]

#GitHub CLI setup
log "🔑 Setting up GitHub CLI..."
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh -y
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

# Start script for kiosk frontend
sudo tee $MAIN_DIR/kiosk/start-server.sh << EOF
#!/bin/bash
npm run preview -- --port 3000 --host
EOF
chmod +x $MAIN_DIR/kiosk/start-server.sh

# Start script for external display
sudo tee $MAIN_DIR/external/start-server.sh << EOF
#!/bin/bash
npm run preview -- --port 5173 --host
EOF
chmod +x $MAIN_DIR/external/start-server.sh

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
ExecStartPre=/bin/bash -c 'until curl -s http://localhost:3000 >/dev/null || [ $? -eq 7 ]; do sleep 1; done'
ExecStart=$MAIN_DIR/kiosk/start-server.sh
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
ExecStartPre=/bin/bash -c 'until curl -s http://localhost:5173 >/dev/null || [ $? -eq 7 ]; do sleep 1; done'
ExecStart=$MAIN_DIR/external/start-server.sh
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/external.log
StandardError=append:$LOG_DIR/external.error.log

[Install]
WantedBy=graphical.target
EOF

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