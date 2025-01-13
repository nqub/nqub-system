# NQUB Token Dispenser System

Complete token dispenser system with kiosk mode and external display support.

## Quick Installation

1. Install Raspberry Pi OS with Desktop
2. Connect both displays to your Raspberry Pi
3. Open terminal and run:
   ```bash
   curl -sSL https://raw.githubusercontent.com/nqub/nqub-system/main/install.sh | bash
   ```

## What Gets Installed

- Backend service (Python) - Handles token dispensing logic
- Kiosk application - Runs on primary display
- External display application - Runs on secondary display

## Managing the System

### View Application Status
```bash
sudo systemctl status nqub-backend
sudo systemctl status nqub-kiosk
sudo systemctl status nqub-external
```

### Update All Applications
```bash
~/nqub-system/update.sh
```

### View Logs
```bash
tail -f /var/log/nqub/backend.log
tail -f /var/log/nqub/kiosk.log
tail -f /var/log/nqub/external.log
```

### Restart Individual Services
```bash
sudo systemctl restart nqub-backend
sudo systemctl restart nqub-kiosk
sudo systemctl restart nqub-external
```

## Display Configuration

- Primary display shows the kiosk interface
- Secondary display shows the external display application
- Screen configuration is handled automatically on startup

## Troubleshooting

1. If screens are swapped:
   ```bash
   sudo systemctl restart nqub-screen-config
   ```

2. If services fail to start:
   ```bash
   sudo systemctl reset-failed
   sudo systemctl restart nqub-backend nqub-kiosk nqub-external
   ```

3. To check for errors:
   ```bash
   journalctl -u nqub-backend -n 50
   journalctl -u nqub-kiosk -n 50
   journalctl -u nqub-external -n 50
   ```