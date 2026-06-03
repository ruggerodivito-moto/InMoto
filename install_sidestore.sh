#!/usr/bin/env bash
# install_sidestore.sh — Scarica e installa SideStore sull'iPhone
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

PAIR_FILE="$HOME/sidestore_pairing.mobiledevicepairing"
SIDESTORE_IPA="$HOME/SideStore.ipa"
SIDESTORE_URL="https://github.com/SideStore/SideStore/releases/latest/download/SideStore.ipa"

echo "========================================"
echo " Installa SideStore su iPhone"
echo "========================================"

# 1. Verifica pairing
if [ ! -f "$PAIR_FILE" ]; then
    echo -e "${RED}✗ Pairing file non trovato. Esegui prima: bash pair_iphone.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Pairing file trovato${NC}"

# 2. Scarica SideStore
echo ""
echo "Scarico SideStore (ultima versione)..."
if [ ! -f "$SIDESTORE_IPA" ]; then
    curl -L -o "$SIDESTORE_IPA" "$SIDESTORE_URL" --progress-bar
    echo -e "${GREEN}✓ SideStore scaricato: $(du -sh $SIDESTORE_IPA | cut -f1)${NC}"
else
    echo -e "${GREEN}✓ SideStore già scaricato${NC}"
fi

# 3. Installa SideStore
echo ""
echo "Installo SideStore sull'iPhone..."
echo -e "${YELLOW}Nota: SideStore richiede firma con il tuo Apple ID.${NC}"
echo ""
echo "Metodo: pymobiledevice3 con Apple ID..."
echo ""
read -p "Email Apple ID: " APPLE_ID
read -s -p "Password Apple ID: " APPLE_PASS
echo ""

# pymobiledevice3 con credenziali Apple ID per firma e installazione
python3 << PYEOF
import subprocess, sys, os

apple_id   = "$APPLE_ID"
apple_pass = "$APPLE_PASS"
ipa_path   = "$SIDESTORE_IPA"
pair_file  = "$PAIR_FILE"

print("Tentativo installazione via pymobiledevice3...")
try:
    result = subprocess.run(
        ["python3", "-m", "pymobiledevice3", "apps", "install", ipa_path],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode == 0:
        print("✓ SideStore installato!")
    else:
        print(f"Output: {result.stdout}")
        print(f"Errore: {result.stderr}")
        sys.exit(1)
except Exception as e:
    print(f"Errore: {e}")
    sys.exit(1)
PYEOF

EXIT=$?
if [ $EXIT -ne 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠ Installazione diretta non riuscita.${NC}"
    echo ""
    echo "ALTERNATIVA — Installa SideStore via web:"
    echo ""
    echo "  1. Apri Safari su iPhone"
    echo "  2. Vai su: https://sidestore.io"
    echo "  3. Segui le istruzioni → installa SideStore via OTA con il tuo Apple ID"
    echo ""
    echo "  Oppure usa AltStore via Windows (Sideloadly gratuito):"
    echo "  https://sideloadly.io"
fi

echo ""
echo "========================================"
echo " PROSSIMI PASSI dopo aver installato SideStore:"
echo ""
echo "1. Apri SideStore sull'iPhone"
echo "2. Accedi con il tuo Apple ID"
echo "3. Attiva WireGuard: SideStore → Impostazioni → Enable WireGuard"
echo "4. Copia il pairing file su iPhone:"
echo "   bash airdrop_pairing.sh"
echo ""
echo "5. Poi installa InMoto:"
echo "   bash install_app.sh InMoto.ipa"
echo "   OPPURE carica l'IPA direttamente in SideStore"
echo "========================================"
