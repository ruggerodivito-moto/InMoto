#!/usr/bin/env bash
# setup_github.sh <GITHUB_USERNAME>
# Da eseguire UNA VOLTA SOLA per configurare il repository

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

GITHUB_USER="${1:-}"

if [ -z "$GITHUB_USER" ]; then
    echo -e "${RED}Uso: bash setup_github.sh TUO_USERNAME_GITHUB${NC}"
    echo ""
    echo "Esempio: bash setup_github.sh mario_rossi"
    exit 1
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} Setup InMoto → GitHub${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "Username: ${GREEN}$GITHUB_USER${NC}"
echo ""

# ── Sostituisce GITHUB_USER in tutti i file ───────────────────────────────────
echo "1. Aggiorno i file con il tuo username..."

FILES_TO_UPDATE=(
    "apps.json"
    "install/windows/installa.bat"
    "install/windows/installa.ps1"
    "install/mac/installa.command"
    "install/sidestore/AGGIUNGI_SORGENTE.md"
    "install/LEGGIMI.md"
    "README.md"
    "codemagic.yaml"
)

for f in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$f" ]; then
        sed -i "s/GITHUB_USER/$GITHUB_USER/g" "$f"
        echo -e "   ${GREEN}✓${NC} $f"
    fi
done

# ── Git init ──────────────────────────────────────────────────────────────────
echo ""
echo "2. Inizializzo repository git..."

if [ ! -d ".git" ]; then
    git init
    git branch -M main
    echo -e "   ${GREEN}✓${NC} Repository inizializzato"
else
    echo -e "   ${GREEN}✓${NC} Repository già esistente"
fi

# .gitignore
cat > .gitignore << 'EOF'
*.xcodeproj/
*.xcworkspace/
build/
DerivedData/
.DS_Store
Pods/
*.ipa
!InMoto/Resources/routes.json
EOF
echo -e "   ${GREEN}✓${NC} .gitignore creato"

git add .
git commit -m "Initial InMoto iOS project" 2>/dev/null || \
    echo -e "   ${YELLOW}(commit già esistente, ok)${NC}"

# ── Crea repo GitHub ──────────────────────────────────────────────────────────
echo ""
echo "3. Creo repository su GitHub..."

if command -v gh &>/dev/null; then
    # GitHub CLI disponibile
    if gh repo view "$GITHUB_USER/InMoto" &>/dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} Repository già esistente su GitHub"
    else
        gh repo create "$GITHUB_USER/InMoto" \
            --public \
            --description "App iOS per itinerari moto italiani" \
            --source=. \
            --push
        echo -e "   ${GREEN}✓${NC} Repository creato e codice pubblicato!"
    fi
    git push -u origin main 2>/dev/null || true
else
    # GitHub CLI non disponibile — istruzioni manuali
    echo -e "   ${YELLOW}GitHub CLI non installato. Fai manualmente:${NC}"
    echo ""
    echo "   a) Vai su https://github.com/new"
    echo "   b) Repository name: InMoto"
    echo "   c) Visibilità: PUBLIC (obbligatorio per build gratuite)"
    echo "   d) NON aggiungere README/gitignore (li abbiamo già)"
    echo "   e) Copia l'URL del repository e incollalo qui sotto:"
    echo ""
    read -p "   URL repository GitHub: " REPO_URL
    if [ -n "$REPO_URL" ]; then
        git remote add origin "$REPO_URL" 2>/dev/null || \
            git remote set-url origin "$REPO_URL"
        git push -u origin main
        echo -e "   ${GREEN}✓${NC} Codice pubblicato!"
    fi
fi

# ── Rende eseguibili gli script ───────────────────────────────────────────────
chmod +x install/mac/installa.command 2>/dev/null || true

# ── Riepilogo finale ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN} Setup completato!${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "Repository: ${CYAN}https://github.com/$GITHUB_USER/InMoto${NC}"
echo -e "Actions:    ${CYAN}https://github.com/$GITHUB_USER/InMoto/actions${NC}"
echo -e "Sorgente:   ${CYAN}https://raw.githubusercontent.com/$GITHUB_USER/InMoto/main/apps.json${NC}"
echo ""
echo "PROSSIMI PASSI:"
echo ""
echo "1. Vai su https://github.com/$GITHUB_USER/InMoto/actions"
echo "   → aspetta che il build finisca (~15 min)"
echo ""
echo "2. Configura Codemagic su https://codemagic.io per firmare l'IPA"
echo ""
echo "3. Porta la cartella install/ su un PC Windows o Mac"
echo "   ed esegui installa.bat (Windows) o installa.command (Mac)"
echo ""
echo "Leggi: install/LEGGIMI.md per le istruzioni complete"
echo ""
