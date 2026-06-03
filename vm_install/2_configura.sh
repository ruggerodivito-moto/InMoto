#!/usr/bin/env bash
# ============================================================
# STEP 2 — Configura credenziali Codemagic e GitHub
# Esegui UNA VOLTA SOLA dopo aver creato il repo e Codemagic
# ============================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$HOME/.inmoto_config"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  InMoto — Configurazione credenziali${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "Inserisci le seguenti informazioni."
echo "Vengono salvate in: $CONFIG_FILE"
echo ""

# GitHub username
read -p "Username GitHub (es. mario_rossi): " GITHUB_USER
while [ -z "$GITHUB_USER" ]; do
    read -p "Username GitHub (obbligatorio): " GITHUB_USER
done

# Codemagic API token
echo ""
echo -e "${YELLOW}Token API Codemagic:${NC}"
echo "  Vai su: https://codemagic.io/teams → seleziona il team → API token"
echo ""
read -p "Token Codemagic (es. abc123...): " CODEMAGIC_TOKEN
while [ -z "$CODEMAGIC_TOKEN" ]; do
    read -p "Token Codemagic (obbligatorio): " CODEMAGIC_TOKEN
done

# Codemagic App ID
echo ""
echo -e "${YELLOW}App ID Codemagic:${NC}"
echo "  Vai su: https://codemagic.io/apps → clic su InMoto"
echo "  L'ID è nell'URL: codemagic.io/app/QUESTO_E_L_ID/..."
echo ""
read -p "App ID Codemagic (es. 65abc...): " CODEMAGIC_APP_ID
while [ -z "$CODEMAGIC_APP_ID" ]; do
    read -p "App ID Codemagic (obbligatorio): " CODEMAGIC_APP_ID
done

# Salva configurazione
cat > "$CONFIG_FILE" << CONF
GITHUB_USER="$GITHUB_USER"
CODEMAGIC_TOKEN="$CODEMAGIC_TOKEN"
CODEMAGIC_APP_ID="$CODEMAGIC_APP_ID"
CODEMAGIC_WORKFLOW="ios-personal-free"
CONF

chmod 600 "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✓ Configurazione salvata in $CONFIG_FILE${NC}"
echo ""

# Verifica connessione Codemagic
echo "Verifico connessione a Codemagic..."
RESP=$(curl -sf -H "x-auth-token: $CODEMAGIC_TOKEN" \
    "https://api.codemagic.io/apps/$CODEMAGIC_APP_ID" 2>/dev/null || echo "ERROR")

if echo "$RESP" | grep -q '"_id"'; then
    APP_NAME=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('appName',''))" 2>/dev/null || echo "InMoto")
    echo -e "${GREEN}✓ Connessione OK — App: $APP_NAME${NC}"
else
    echo -e "${YELLOW}⚠ Impossibile verificare. Controlla token e App ID.${NC}"
    echo "  (puoi continuare comunque)"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Configurazione completata!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "PROSSIMO PASSO:"
echo ""
echo "  Connetti iPhone al PC via cavo USB, poi:"
echo "  bash 3_pair_e_installa.sh"
echo ""
