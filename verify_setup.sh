#!/bin/bash

# Configuration
MAIN_DIR="$HOME/nqub-system"
LOG_DIR="/var/log/nqub"
VENV_DIR="$MAIN_DIR/venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] $1${NC}"
    else
        echo -e "${RED}[✗] $1${NC}"
        echo -e "${YELLOW}Fix: $2${NC}"
    fi
}

echo "Verifying NQUB System Setup..."

# 1. Check directory structure
echo -e "\nChecking directory structure:"
[ -d "$MAIN_DIR" ] && check_status "Main directory exists" "Create directory: mkdir -p $MAIN_DIR"
[ -d "$MAIN_DIR/backend" ] && check_status "Backend directory exists" "Clone repository"
[ -d "$VENV_DIR" ] && check_status "Virtual environment exists" "Create virtualenv: python -m venv $VENV_DIR"

# 2. Check permissions
echo -e "\nChecking permissions:"
[ -r "$MAIN_DIR/backend" ] && [ -x "$MAIN_DIR/backend" ] && check_status "Backend directory permissions" "Fix permissions: chmod 755 $MAIN_DIR/backend"
[ -w "$LOG_DIR" ] && check_status "Log directory writable" "Fix permissions: sudo chown -R $USER:$USER $LOG_DIR"

# 3. Check Python environment
echo -e "\nChecking Python environment:"
source $VENV_DIR/bin/activate 2>/dev/null
if [ $? -eq 0 ]; then
    check_status "Virtual environment activation" "Recreate virtualenv"
    
    # Check Python packages
    echo -e "\nChecking required Python packages:"
    pip freeze | grep -q "pyserial" && check_status "pyserial installed" "pip install pyserial"
    # Add other required packages here
else
    echo -e "${RED}[✗] Virtual environment not working${NC}"
    echo -e "${YELLOW}Fix: Remove and recreate virtualenv${NC}"
fi

# 4. Check service configuration
echo -e "\nChecking service configuration:"
sudo test -f /etc/systemd/system/nqub-backend-main.service && check_status "Backend service exists" "Reinstall service file"
sudo systemctl is-active --quiet nqub-backend-main && check_status "Backend service is running" "Start service: sudo systemctl start nqub-backend-main"

# 5. Check device permissions
echo -e "\nChecking device permissions:"
groups $USER | grep -q "dialout" && check_status "User in dialout group" "Add user to group: sudo usermod -a -G dialout $USER"
[ -e "/dev/ttyUSB0" ] && check_status "USB device exists" "Check USB connection"
ls -l /dev/ttyUSB0 | grep -q "dialout" && check_status "USB device has correct group" "Fix udev rules"

# 6. Check logs for errors
echo -e "\nChecking recent logs for errors:"
sudo journalctl -u nqub-backend-main -n 50 --no-pager | grep -i "error"

echo -e "\nVerification complete. Check the items marked with [✗] above and apply the suggested fixes."