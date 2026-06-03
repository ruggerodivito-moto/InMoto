#!/usr/bin/env bash
# ============================================================
# STEP 4 — Reinstalla IPA (ogni 7 giorni o dopo aggiornamenti)
# Molto più veloce del primo avvio: avvia build, aspetta, installa
# ============================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$HOME/.inmoto_config"
WORK_DIR="$HOME/.inmoto_work"

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; exit 1; }
info() { echo -e "    $1"; }

[ -f "$CONFIG_FILE" ] || err "Configurazione non trovata. Esegui prima: bash 2_configura.sh"
source "$CONFIG_FILE"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  InMoto — Reinstallazione${NC}"
echo -e "${CYAN}================================================${NC}"

# Se c'è già un IPA locale, usa quello
EXISTING_IPA="$WORK_DIR/InMoto.ipa"
BUILD_ID="${1:-}"

if [ -n "$BUILD_ID" ]; then
    # Build ID passato come argomento — scarica direttamente
    echo ""
    echo "Scarico IPA dal build $BUILD_ID..."
    ARTIFACT_URL=$(curl -sf \
        -H "x-auth-token: $CODEMAGIC_TOKEN" \
        "https://api.codemagic.io/builds/$BUILD_ID" 2>/dev/null | \
        python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    b = d.get('build',d)
    for a in b.get('artefacts', b.get('artifacts',[])):
        if a.get('name','').endswith('.ipa'):
            print(a.get('url',''))
            break
except: pass
" 2>/dev/null)

elif [ -f "$EXISTING_IPA" ]; then
    # IPA già presente — chiede se vuoi usarlo o farne uno nuovo
    IPA_DATE=$(stat -c '%y' "$EXISTING_IPA" 2>/dev/null | cut -d' ' -f1)
    echo ""
    echo -e "  IPA trovato in locale (data: ${YELLOW}$IPA_DATE${NC})"
    echo -e "  Hai due opzioni:"
    echo "  [1] Usa l'IPA esistente (più veloce)"
    echo "  [2] Compila una nuova versione su Codemagic (~15 min)"
    echo ""
    read -p "  Scelta [1/2]: " CHOICE
    if [ "$CHOICE" = "1" ]; then
        echo ""
        info "Uso IPA esistente: $EXISTING_IPA"
        ARTIFACT_URL=""
        BUILD_ID=""
    else
        BUILD_ID=""
        ARTIFACT_URL=""
        # Avvia nuovo build (richiama lo script principale)
        exec bash "$(dirname $0)/3_pair_e_installa.sh"
    fi
else
    # Nessun IPA — avvia build
    exec bash "$(dirname $0)/3_pair_e_installa.sh"
fi

# Scarica se abbiamo un URL
if [ -n "$ARTIFACT_URL" ]; then
    curl -fL --progress-bar \
        -H "x-auth-token: $CODEMAGIC_TOKEN" \
        -o "$EXISTING_IPA" "$ARTIFACT_URL"
    ok "IPA aggiornato"
fi

# Installa
echo ""
echo "Installo sull'iPhone..."
sudo systemctl start usbmuxd 2>/dev/null || true
sleep 1

if ideviceinstaller -i "$EXISTING_IPA" 2>&1; then
    ok "InMoto aggiornata!"
elif python3 -m pymobiledevice3 apps install "$EXISTING_IPA" 2>&1; then
    ok "InMoto aggiornata!"
else
    err "Installazione fallita. iPhone connesso e sbloccato?"
fi

echo ""
echo -e "${GREEN}  Fatto! Apri InMoto sull'iPhone.${NC}"
echo ""
