#!/usr/bin/env bash
# ============================================================
# STEP 3 — Pairing iPhone + Build + Installa InMoto
# Esegui con iPhone connesso via USB
# ============================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$HOME/.inmoto_config"
WORK_DIR="$HOME/.inmoto_work"

ok()    { echo -e "${GREEN}  ✓ $1${NC}"; }
err()   { echo -e "${RED}  ✗ $1${NC}"; exit 1; }
info()  { echo -e "    $1"; }
step()  { echo ""; echo -e "${CYAN}[$1] $2${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }

mkdir -p "$WORK_DIR"

# Carica configurazione
[ -f "$CONFIG_FILE" ] || err "Configurazione non trovata. Esegui prima: bash 2_configura.sh"
source "$CONFIG_FILE"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  InMoto — Pairing + Build + Installazione${NC}"
echo -e "${CYAN}================================================${NC}"

# ── STEP A: Verifica iPhone connesso ─────────────────────────────────────────
step A "Verifica iPhone connesso..."

sudo systemctl start usbmuxd 2>/dev/null || true
sleep 1

UDID=$(python3 -m pymobiledevice3 usbmux list 2>/dev/null \
    | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data: print(data[0].get('Udid',''))
except: pass
" 2>/dev/null || \
       ideviceinfo -k UniqueDeviceID 2>/dev/null || echo "")

if [ -z "$UDID" ]; then
    err "iPhone non trovato. Verifica:
  • Cavo USB collegato
  • iPhone sbloccato
  • Developer Mode attivo (Impostazioni → Privacy e sicurezza → Modalità sviluppatore)"
fi

IOS_VER=$(ideviceinfo -k ProductVersion 2>/dev/null || \
          python3 -m pymobiledevice3 usbmux list 2>/dev/null | \
          python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('ProductVersion',''))" 2>/dev/null || \
          echo "sconosciuta")

ok "iPhone trovato"
info "UDID: $UDID"
info "iOS:  $IOS_VER"

# Salva UDID per uso futuro
echo "$UDID" > "$WORK_DIR/udid.txt"

# ── STEP B: Pairing ───────────────────────────────────────────────────────────
step B "Pairing iPhone ↔ Linux VM..."
info "Se appare un popup sull'iPhone: tocca 'Fidati'"
echo ""

if sudo python3 -m pymobiledevice3 usbmux pair 2>&1 | grep -qi "success\|already\|ok\|pair"; then
    ok "Pairing completato"
else
    # Prova con idevicepair
    if idevicepair pair 2>&1 | grep -qi "success\|already"; then
        ok "Pairing completato (idevicepair)"
    else
        warn "Pairing non confermato — continuo comunque"
        info "Assicurati di aver toccato 'Fidati' sull'iPhone"
    fi
fi

# Salva pairing file per SideStore
sudo python3 -m pymobiledevice3 usbmux save-pair-record \
    "$WORK_DIR/sidestore.mobiledevicepairing" 2>/dev/null || true

# ── STEP C: Avvia build su Codemagic ─────────────────────────────────────────
step C "Avvio build su Codemagic..."
info "Questo compila e firma l'IPA con il tuo Apple ID (gratis, ~15 min)"
echo ""

BUILD_PAYLOAD=$(python3 - << PYEOF
import json
payload = {
    "appId": "$CODEMAGIC_APP_ID",
    "workflowId": "$CODEMAGIC_WORKFLOW",
    "branch": "main"
}
print(json.dumps(payload))
PYEOF
)

BUILD_RESP=$(curl -sf \
    -H "x-auth-token: $CODEMAGIC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BUILD_PAYLOAD" \
    "https://api.codemagic.io/builds" 2>/dev/null)

BUILD_ID=$(echo "$BUILD_RESP" | python3 -c \
    "import json,sys; print(json.load(sys.stdin).get('buildId',''))" 2>/dev/null)

if [ -z "$BUILD_ID" ]; then
    echo ""
    warn "Codemagic non raggiungibile o configurazione errata."
    echo ""
    info "ALTERNATIVA: scarica manualmente l'IPA da Codemagic:"
    info "  1. Vai su https://codemagic.io → InMoto → avvia build manualmente"
    info "  2. Scarica l'IPA e copialo qui: $WORK_DIR/InMoto.ipa"
    info "  3. Poi esegui: bash 4_installa_ipa.sh"
    exit 0
fi

ok "Build avviato!"
info "Build ID: $BUILD_ID"
info "Puoi seguire il progresso su: https://codemagic.io/build/$BUILD_ID"
echo ""

# ── STEP D: Attendi completamento build ───────────────────────────────────────
step D "Attendo completamento build (max 25 minuti)..."
echo ""

MAX_WAIT=1500   # 25 minuti
POLL=20         # controlla ogni 20 secondi
ELAPSED=0
STATUS=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    BUILD_STATUS=$(curl -sf \
        -H "x-auth-token: $CODEMAGIC_TOKEN" \
        "https://api.codemagic.io/builds/$BUILD_ID" 2>/dev/null | \
        python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    b = d.get('build', d)
    print(b.get('status', ''))
except: print('')
" 2>/dev/null)

    case "$BUILD_STATUS" in
        "finished")
            ok "Build completato!"
            STATUS="finished"
            break
            ;;
        "failed"|"error"|"canceled")
            err "Build fallito (status: $BUILD_STATUS). Controlla su Codemagic."
            ;;
        *)
            printf "\r    In coda/building... (%d/%d sec)  " $ELAPSED $MAX_WAIT
            ;;
    esac

    sleep $POLL
    ELAPSED=$((ELAPSED + POLL))
done

if [ "$STATUS" != "finished" ]; then
    echo ""
    warn "Timeout — build ancora in corso."
    info "Quando completa, esegui: bash 4_installa_ipa.sh $BUILD_ID"
    exit 0
fi

# ── STEP E: Scarica IPA ───────────────────────────────────────────────────────
step E "Scarico IPA firmato..."

ARTIFACT_URL=$(curl -sf \
    -H "x-auth-token: $CODEMAGIC_TOKEN" \
    "https://api.codemagic.io/builds/$BUILD_ID" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    b = d.get('build', d)
    arts = b.get('artefacts', b.get('artifacts', []))
    for a in arts:
        url = a.get('url','')
        name = a.get('name','')
        if url and name.endswith('.ipa'):
            print(url)
            break
except Exception as e:
    pass
" 2>/dev/null)

if [ -z "$ARTIFACT_URL" ]; then
    warn "URL artifact non trovato. Scarica manualmente da Codemagic."
    info "Posiziona il file in: $WORK_DIR/InMoto.ipa"
    info "Poi esegui: bash 4_installa_ipa.sh"
    exit 0
fi

IPA_PATH="$WORK_DIR/InMoto.ipa"
curl -fL --progress-bar \
    -H "x-auth-token: $CODEMAGIC_TOKEN" \
    -o "$IPA_PATH" "$ARTIFACT_URL"

SIZE=$(du -sh "$IPA_PATH" 2>/dev/null | cut -f1)
ok "InMoto.ipa scaricato ($SIZE)"

# ── STEP F: Installa sull'iPhone ──────────────────────────────────────────────
step F "Installo InMoto sull'iPhone..."
echo ""
info "Sblocca l'iPhone se necessario"
echo ""

install_ipa() {
    local IPA="$1"
    # Metodo 1: ideviceinstaller (più stabile)
    if command -v ideviceinstaller &>/dev/null; then
        ideviceinstaller -i "$IPA" 2>&1 && return 0
    fi
    # Metodo 2: pymobiledevice3
    python3 -m pymobiledevice3 apps install "$IPA" 2>&1 && return 0
    return 1
}

if install_ipa "$IPA_PATH"; then
    echo ""
    ok "InMoto installata sull'iPhone!"
else
    echo ""
    warn "Installazione non riuscita. Possibili cause:"
    info "• L'iPhone non è in Developer Mode"
    info "  (Impostazioni → Privacy e sicurezza → Modalità sviluppatore → ON)"
    info "• Il pairing non è stato completato"
    info "• Il profilo di provisioning non include il tuo UDID in Codemagic"
    echo ""
    info "Risolto? Riesegui: bash 4_installa_ipa.sh"
fi

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  Installazione completata!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "COSA FARE ORA:"
echo ""
echo -e "  1. Sull'iPhone apri ${CYAN}InMoto${NC}"
echo -e "  2. Tab Impostazioni → inserisci URL server e API key"
echo ""
echo -e "  Per il ${YELLOW}rinnovo automatico${NC} (evita di rifare tutto ogni 7 giorni):"
echo -e "  Apri Safari sull'iPhone → ${CYAN}sidestore.io${NC} → installa SideStore"
echo ""
echo -e "  Per reinstallare manualmente tra 7 giorni:"
echo -e "  ${CYAN}bash 4_installa_ipa.sh${NC}  (molto più veloce del primo avvio)"
echo ""

# Salva Build ID per uso futuro
echo "$BUILD_ID" > "$WORK_DIR/last_build_id.txt"
