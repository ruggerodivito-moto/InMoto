#!/usr/bin/env bash
# pair_iphone.sh — Accoppia iPhone con Linux e genera il pairing file per SideStore
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo "========================================"
echo " Pairing iPhone → Linux"
echo "========================================"
echo ""
echo "Assicurati che:"
echo "  • iPhone sia connesso via cavo USB"
echo "  • Schermo iPhone sia sbloccato"
echo "  • Developer Mode sia attivo"
echo ""
read -p "Premi INVIO quando pronto..."

# Verifica device
echo ""
echo "Cerco iPhone connesso..."
UDID=$(python3 -m pymobiledevice3 usbmux list 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data: print(data[0].get('Udid',''))
" 2>/dev/null || ideviceinfo -k UniqueDeviceID 2>/dev/null || echo "")

if [ -z "$UDID" ]; then
    echo -e "${RED}✗ iPhone non trovato. Verifica il cavo e riprova.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ iPhone trovato: UDID = $UDID${NC}"

# iOS version
IOS_VER=$(ideviceinfo -k ProductVersion 2>/dev/null || echo "sconosciuta")
echo -e "${GREEN}✓ iOS $IOS_VER${NC}"

# Pairing
echo ""
echo "Avvio pairing (dovrebbe apparire un popup sull'iPhone: tocca 'Fidati')..."
sudo python3 -m pymobiledevice3 usbmux pair
echo -e "${GREEN}✓ Pairing completato${NC}"

# Salva pairing file per SideStore
PAIR_FILE="$HOME/sidestore_pairing.mobiledevicepairing"
echo ""
echo "Salvo pairing file per SideStore..."
sudo python3 -m pymobiledevice3 usbmux save-pair-record "$PAIR_FILE" 2>/dev/null || \
    sudo pymobiledevice3 usbmux save-pair-record "$PAIR_FILE" 2>/dev/null || \
    python3 -m pymobiledevice3 usbmux save-pair-record "$PAIR_FILE"
echo -e "${GREEN}✓ Pairing file salvato: $PAIR_FILE${NC}"

# Salva UDID
echo "$UDID" > "$HOME/iphone_udid.txt"

echo ""
echo "========================================"
echo " Pairing completato!"
echo ""
echo "UDID salvato in: ~/iphone_udid.txt"
echo "Pairing file:    ~/sidestore_pairing.mobiledevicepairing"
echo ""
echo "PROSSIMI PASSI:"
echo "  1. bash install_sidestore.sh    ← installa SideStore"
echo "  2. bash install_app.sh <file.ipa>  ← installa InMoto"
echo "========================================"
