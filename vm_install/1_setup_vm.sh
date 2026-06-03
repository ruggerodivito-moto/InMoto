#!/usr/bin/env bash
# ============================================================
# STEP 1 — Esegui UNA VOLTA SOLA sulla VM Linux
# Installa tutti gli strumenti necessari
# ============================================================
# Uso: bash 1_setup_vm.sh
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "    $1"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  InMoto — Setup VM Linux${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Dipendenze sistema
echo "Installo dipendenze sistema..."
sudo apt-get update -qq
sudo apt-get install -y \
    python3 python3-pip \
    libimobiledevice-utils \
    ideviceinstaller \
    usbmuxd \
    libusbmuxd-tools \
    curl jq unzip \
    2>/dev/null
ok "Dipendenze sistema installate"

# pymobiledevice3 (iOS 26 support)
echo ""
echo "Installo pymobiledevice3..."
pip3 install --upgrade --quiet pymobiledevice3
ok "pymobiledevice3 installato ($(python3 -m pymobiledevice3 --version 2>/dev/null || echo 'ok'))"

# usbmuxd service
echo ""
echo "Avvio usbmuxd..."
sudo systemctl enable usbmuxd --now 2>/dev/null || sudo service usbmuxd start 2>/dev/null || true
ok "usbmuxd attivo"

# Regole udev — accesso iPhone senza sudo
echo ""
echo "Configuro accesso USB iPhone..."
cat | sudo tee /etc/udev/rules.d/99-iphone.rules > /dev/null << 'UDEV'
SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", MODE="0666", GROUP="plugdev"
UDEV
sudo udevadm control --reload-rules 2>/dev/null || true
sudo usermod -aG plugdev "$USER" 2>/dev/null || true
ok "Regole udev configurate"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Setup completato!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "PROSSIMO PASSO:"
echo ""
echo -e "  1. Sull'iPhone: ${CYAN}Impostazioni → Privacy e sicurezza${NC}"
echo -e "                  ${CYAN}→ Modalità sviluppatore → Attiva${NC}"
echo ""
echo "  2. Configura Codemagic seguendo le istruzioni in README_CODEMAGIC.md"
echo ""
echo "  3. Esegui:  bash 2_configura.sh"
echo ""
