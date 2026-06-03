#!/usr/bin/env bash
# ============================================================
# Installazione InMoto dalla VM — scarica da GitHub
# Non richiede accesso al server AMT interno
#
# Uso: bash <(curl -fsSL "https://raw.githubusercontent.com/GITHUB_USER/InMoto/main/vm_install/install_from_github.sh")
# ============================================================
set -e

GITHUB_USER="GITHUB_USER"
REPO="https://github.com/$GITHUB_USER/InMoto"
RAW="https://raw.githubusercontent.com/$GITHUB_USER/InMoto/main"
ZIP_URL="https://github.com/$GITHUB_USER/InMoto/archive/refs/heads/main.zip"
INSTALL_DIR="$HOME/inmoto"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; exit 1; }
info() { echo -e "    $1"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  InMoto — Installazione da GitHub${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
info "Repository: $REPO"
echo ""

# Verifica connessione GitHub
echo "Verifico accesso a GitHub..."
curl -fsS --max-time 8 -o /dev/null "$RAW/vm_install/1_setup_vm.sh" 2>/dev/null || \
    err "Impossibile raggiungere GitHub. Verifica la connessione."
ok "GitHub raggiungibile"

# Scarica ZIP del repository
echo ""
echo "Scarico pacchetto da GitHub..."
TMP_ZIP=$(mktemp /tmp/inmoto_XXXXXX.zip)
curl -fsSL --retry 3 -o "$TMP_ZIP" "$ZIP_URL" || \
    err "Download fallito. Il repository è pubblico?"
SIZE=$(du -sh "$TMP_ZIP" | cut -f1)
ok "Scaricato ($SIZE)"

# Estrai
echo ""
echo "Estraggo in $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
TMP_DIR=$(mktemp -d /tmp/inmoto_extract_XXXXXX)
unzip -q -o "$TMP_ZIP" -d "$TMP_DIR"
rm -f "$TMP_ZIP"

# GitHub zippa con la cartella "InMoto-main/" dentro — sposta tutto
EXTRACTED=$(find "$TMP_DIR" -maxdepth 1 -type d | grep -v "^$TMP_DIR$" | head -1)
if [ -n "$EXTRACTED" ]; then
    cp -a "$EXTRACTED/." "$INSTALL_DIR/"
    rm -rf "$TMP_DIR"
else
    cp -a "$TMP_DIR/." "$INSTALL_DIR/"
    rm -rf "$TMP_DIR"
fi

# Permessi eseguibili
find "$INSTALL_DIR" -name "*.sh" -o -name "*.command" | xargs chmod +x 2>/dev/null || true

ok "File estratti in: $INSTALL_DIR"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  Installazione completata!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "  Contenuto installato:"
ls -1 "$INSTALL_DIR/vm_install/" 2>/dev/null | grep "\.sh" | sed 's/^/    /'
echo ""
echo "  PROSSIMO PASSO:"
echo -e "    ${CYAN}cd $INSTALL_DIR && bash vm_install/1_setup_vm.sh${NC}"
echo ""
