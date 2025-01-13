# NQUB System

Complete system installation for NQUB token dispenser system on Raspberry Pi 4, including backend, kiosk interface, and external display.

## Prerequisites

- Raspberry Pi 4 with fresh Raspberry Pi OS installation
- Two HDMI displays connected
- Internet connection
- GitHub account with access to NQUB repositories

## Hardware Setup

1. Connect primary display to HDMI-1
2. Connect secondary display to HDMI-2
3. Connect coin dispenser to USB port
4. Connect QR reader to USB port
5. Ensure CCTalk interface is properly connected

## Installation

1. Prepare Raspberry Pi:
   ```bash
   # Update system
   sudo apt update
   sudo apt full-upgrade -y
   
   # Install git
   sudo apt install -y git
   ```

2. Clone this repository:
   ```bash
   git clone https://github.com/nqub/nqub-system.git
   cd nqub-system
   ```

3. Run the installation script:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

4. During installation:
   - You'll be prompted to authenticate with GitHub
   - Accept any system configuration changes
   - Wait for all components to install and build

## System Components

### Backend (nqub-coin-dispenser)
- Handles hardware communication
- Manages coin dispensing
- Provides API endpoints

### Kiosk Interface (token-dispenser-kiosk)
- Primary screen interface
- User interaction
- Transaction management

### External Display (nqub-coin-dispenser-external-screen)
- Secondary screen interface
- Status display
- Advertisement/Information screen

## Service Management

Check service status:
```bash
sudo systemctl status nqub-backend
sudo systemctl status nqub-kiosk
sudo systemctl status nqub-external
```

Restart services:
```bash
sudo systemctl restart nqub-backend
sudo systemctl restart nqub-kiosk
sudo systemctl restart nqub-external
```

View logs:
```bash
tail -f /var/log/nqub/backend.log
tail -f /var/log/nqub/kiosk.log
tail -f /var/log/nqub/external.log
```

## Troubleshooting

### Display Issues
1. Check display connection:
   ```bash
   xrandr --query
   ```

2. Verify display configuration:
   ```bash
   cat /usr/local/bin/setup-displays
   ```

### Hardware Issues
1. Check USB devices:
   ```bash
   lsusb
   ```

2. Verify serial ports:
   ```bash
   ls -l /dev/ttyUSB*
   ```

3. Test CCTalk interface:
   ```bash
   sudo setserial -g /dev/ttyUSB[01]
   ```

### Service Issues
1. Check service logs in `/var/log/nqub/`
2. Verify service configuration:
   ```bash
   sudo systemctl cat nqub-backend
   sudo systemctl cat nqub-kiosk
   sudo systemctl cat nqub-external
   ```

## Security Notes

1. The system runs in kiosk mode with restricted access
2. Services run with minimal required permissions
3. All external URLs are blocked in kiosk mode
4. System automatically updates on restart

## Update System

The system can be updated by pulling the latest changes:
```bash
cd ~/nqub-system
git pull
./install.sh
```