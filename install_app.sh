#!/usr/bin/env bash
# install_app.sh <percorso.ipa> — Installa un IPA firmato sull'iPhone via USB
set -e
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

IPA="$1"
if [ -z "$IPA" ]; then
    echo -e "${RED}Uso: bash install_app.sh percorso/app.ipa${NC}"
    exit 1
fi
if [ ! -f "$IPA" ]; then
    echo -e "${RED}File non trovato: $IPA${NC}"
    exit 1
fi

echo "========================================"
echo " Installo: $(basename $IPA)"
echo "========================================"
echo ""
echo "Assicurati che iPhone sia connesso e sbloccato."
echo ""

# Prova pymobiledevice3 (metodo principale per iOS 26)
install_via_pymobiledevice3() {
    echo "Metodo 1: pymobiledevice3..."
    python3 -m pymobiledevice3 apps install "$IPA" && return 0 || return 1
}

# Fallback: ideviceinstaller
install_via_ideviceinstaller() {
    echo "Metodo 2: ideviceinstaller..."
    ideviceinstaller -i "$IPA" && return 0 || return 1
}

if install_via_pymobiledevice3; then
    echo -e "${GREEN}✓ App installata con pymobiledevice3${NC}"
elif install_via_ideviceinstaller; then
    echo -e "${GREEN}✓ App installata con ideviceinstaller${NC}"
else
    echo -e "${RED}✗ Installazione fallita.${NC}"
    echo ""
    echo "Possibili cause:"
    echo "  • iPhone non in Developer Mode (Impostazioni → Privacy e sicurezza → Modalità sviluppatore)"
    echo "  • IPA non firmato correttamente"
    echo "  • Pairing non completato (riesegui pair_iphone.sh)"
    exit 1
fi

echo ""
echo "========================================"
echo -e " ${GREEN}Installazione completata!${NC}"
echo " Apri l'app sull'iPhone."
echo "========================================"
