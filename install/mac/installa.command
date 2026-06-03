#!/usr/bin/env bash
# InMoto Installer — macOS
# Doppio click per avviare (file .command si apre nel Terminale)
# Se macOS blocca il file: tasto destro → Apri → Apri

ruggerodivito-moto="ruggerodivito-moto"
WORK_DIR="$HOME/Downloads/InMotoInstaller"
IPA_URL="https://github.com/$ruggerodivito-moto/InMoto/releases/latest/download/InMoto.ipa"
IPA_PATH="$WORK_DIR/InMoto.ipa"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

header() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${WHITE}   InMoto — Installatore per iPhone${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""
}

step() { echo -e "${YELLOW}[$1] $2${NC}"; }
ok()   { echo -e "${GREEN}    ✓ $1${NC}"; }
err()  { echo -e "${RED}    ✗ $1${NC}"; }
info() { echo -e "      $1"; }

header
mkdir -p "$WORK_DIR"

# ── STEP 1: Scarica IPA ───────────────────────────────────────────────────────
step 1 "Scarico InMoto.ipa da GitHub Releases..."

if curl -fL --progress-bar -o "$IPA_PATH" "$IPA_URL"; then
    SIZE=$(du -sh "$IPA_PATH" | cut -f1)
    ok "InMoto.ipa scaricato ($SIZE)"
else
    err "Download fallito. Verifica che il repo sia pubblico e abbia una Release."
    info "URL: $IPA_URL"
    echo ""
    read -p "Premi INVIO per uscire..."
    exit 1
fi

# ── STEP 2: Scegli metodo di installazione ────────────────────────────────────
echo ""
step 2 "Scegli il metodo di installazione:"
echo ""
echo "  [1] AltStore (consigliato — gestisce rinnovo automatico)"
echo "  [2] Sideloadly (più semplice, stesso di Windows)"
echo "  [3] Xcode / Apple Configurator 2 (se li hai già installati)"
echo ""
read -p "Scelta [1-3]: " METHOD
echo ""

case "$METHOD" in
    1)
        # ── AltServer ─────────────────────────────────────────────────────────
        step 3 "Installo AltStore via AltServer..."
        echo ""

        ALTSERVER_URL="https://cdn.altstore.io/file/altstore/altserver.zip"
        ALTSERVER_ZIP="$WORK_DIR/altserver.zip"
        ALTSERVER_APP="/Applications/AltServer.app"

        if [ -d "$ALTSERVER_APP" ]; then
            ok "AltServer già installato"
        else
            info "Scarico AltServer..."
            curl -fL --progress-bar -o "$ALTSERVER_ZIP" "$ALTSERVER_URL"
            unzip -q "$ALTSERVER_ZIP" -d "$WORK_DIR/altserver_extracted"
            ALTSERVER_FOUND=$(find "$WORK_DIR/altserver_extracted" -name "AltServer.app" | head -1)
            if [ -n "$ALTSERVER_FOUND" ]; then
                sudo cp -r "$ALTSERVER_FOUND" /Applications/
                ok "AltServer installato in /Applications"
            else
                err "AltServer.app non trovato nel zip"
            fi
        fi

        echo ""
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${WHITE}  ISTRUZIONI ALTSTORE${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo ""
        info "1. Apri AltServer dal Launchpad o da /Applications"
        info "2. Connetti iPhone con cavo USB"
        info "3. Nell'icona AltServer nella barra menu: Install AltStore → seleziona iPhone"
        info "4. Inserisci il tuo Apple ID quando richiesto"
        info "5. Su iPhone: Impostazioni → Generali → Gestione VPN e dispositivo"
        info "   → Fidati del profilo con la tua email Apple ID"
        info "6. In AltStore → Library → + → seleziona '$IPA_PATH'"
        echo ""
        info "AltStore rinnova automaticamente i certificati ogni 7 giorni."
        echo ""

        # Apri AltServer
        open "$ALTSERVER_APP" 2>/dev/null || true
        # Apri Finder sulla cartella con l'IPA
        open "$WORK_DIR"
        ok "AltServer aperto e cartella InMoto aperta in Finder"
        ;;

    2)
        # ── Sideloadly ────────────────────────────────────────────────────────
        step 3 "Scarico Sideloadly per Mac..."
        echo ""

        SIDELOADLY_URL="https://sideloadly.io/SideloadlySetup.dmg"
        SIDELOADLY_DMG="$WORK_DIR/Sideloadly.dmg"
        SIDELOADLY_APP="/Applications/Sideloadly.app"

        if [ -d "$SIDELOADLY_APP" ]; then
            ok "Sideloadly già installato"
        else
            curl -fL --progress-bar -o "$SIDELOADLY_DMG" "$SIDELOADLY_URL"
            MOUNT_POINT=$(hdiutil attach "$SIDELOADLY_DMG" -nobrowse -noautoopen 2>/dev/null | tail -1 | awk '{print $3}')
            if [ -n "$MOUNT_POINT" ]; then
                cp -r "$MOUNT_POINT"/*.app /Applications/ 2>/dev/null || true
                hdiutil detach "$MOUNT_POINT" -quiet
                ok "Sideloadly installato"
            else
                err "Montaggio DMG fallito — apri il DMG manualmente"
                open "$SIDELOADLY_DMG"
            fi
        fi

        echo ""
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${WHITE}  ISTRUZIONI SIDELOADLY${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo ""
        info "1. Connetti iPhone con cavo USB"
        info "2. Sblocca iPhone e tocca 'Fidati' se richiesto"
        info "3. Sideloadly si apre con InMoto.ipa già caricato"
        info "4. Inserisci il tuo Apple ID (GRATUITO)"
        info "5. Clicca Start → inserisci password quando richiesta"
        echo ""

        open -a Sideloadly "$IPA_PATH" 2>/dev/null || \
            open "$SIDELOADLY_APP" 2>/dev/null || true
        open "$WORK_DIR"
        ok "Sideloadly aperto"
        ;;

    3)
        # ── Xcode / Apple Configurator ────────────────────────────────────────
        step 3 "Installazione con strumenti Apple..."
        echo ""

        # Prova devicectl (Xcode 15+)
        if command -v xcrun &>/dev/null; then
            echo "iPhone trovato:"
            xcrun devicectl list devices 2>/dev/null || true
            echo ""
            info "Connetti iPhone, poi esegui:"
            info "xcrun devicectl device install app --device <UDID> '$IPA_PATH'"
            echo ""
            info "Oppure usa Apple Configurator 2 (App Store gratuito):"
            info "Trascina il file '$IPA_PATH' sul tuo iPhone in Configurator"
        else
            err "Xcode non installato"
            info "Installa Xcode da: https://apps.apple.com/app/xcode/id497799835"
        fi

        open "$WORK_DIR"
        ;;

    *)
        err "Scelta non valida"
        ;;
esac

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${GREEN}  PROSSIMO PASSO: SideStore${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""
info "Per il rinnovo AUTOMATICO ogni 7 giorni senza computer:"
info ""
info "1. Apri Safari su iPhone → vai su https://sidestore.io"
info "2. Installa SideStore (usa lo stesso Apple ID)"
info "3. In SideStore → Sources → + → aggiungi:"
info ""
echo -e "${CYAN}   https://raw.githubusercontent.com/$ruggerodivito-moto/InMoto/main/apps.json${NC}"
echo ""
info "4. Da questo momento SideStore aggiorna InMoto automaticamente!"
echo ""
read -p "Premi INVIO per chiudere..."
