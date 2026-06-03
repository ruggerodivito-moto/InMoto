#!/usr/bin/env bash
# setup_linux.sh — Prepara Linux per installare app su iPhone via USB
# Esegui come: bash setup_linux.sh

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo "========================================"
echo " Setup Linux → iPhone via USB"
echo "========================================"

# 1. Dipendenze sistema
echo ""
echo "1. Installo dipendenze sistema..."
sudo apt-get update -q
sudo apt-get install -y \
    python3 python3-pip python3-venv \
    libimobiledevice-utils \
    usbmuxd \
    libusbmuxd-tools \
    ideviceinstaller \
    libssl-dev libffi-dev
ok "Dipendenze sistema installate"

# 2. pymobiledevice3 (versione recente per iOS 26)
echo ""
echo "2. Installo pymobiledevice3..."
pip3 install --upgrade --user pymobiledevice3
ok "pymobiledevice3 installato"

# 3. usbmuxd service
echo ""
echo "3. Avvio usbmuxd..."
sudo systemctl enable usbmuxd 2>/dev/null || true
sudo systemctl start  usbmuxd 2>/dev/null || true
ok "usbmuxd attivo"

# 4. Regole udev per iPhone (accesso senza sudo ogni volta)
echo ""
echo "4. Configuro regole udev per iPhone..."
cat > /tmp/99-iphone.rules << 'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", MODE="0666", GROUP="plugdev"
EOF
sudo cp /tmp/99-iphone.rules /etc/udev/rules.d/99-iphone.rules
sudo udevadm control --reload-rules
sudo usermod -aG plugdev $USER
ok "Regole udev configurate (potrebbe servire logout/login)"

echo ""
echo "========================================"
echo " Setup completato!"
echo ""
echo "PROSSIMI PASSI:"
echo ""
echo "1. Abilita Developer Mode sull'iPhone:"
echo "   Impostazioni → Privacy e sicurezza → Modalità sviluppatore → ON"
echo ""
echo "2. Connetti iPhone con cavo USB"
echo ""
echo "3. Esegui: bash pair_iphone.sh"
echo "========================================"
