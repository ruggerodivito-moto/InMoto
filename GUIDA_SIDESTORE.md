# Guida completa — InMoto su iPhone 15 Pro (iOS 26) con SideStore

## Panoramica

```
Linux                    Codemagic (cloud)         iPhone
  │                           │                       │
  ├─ git push ──────────────► │                       │
  │                    build + firma IPA              │
  │◄──────── scarica .ipa ────┘                       │
  │                                                   │
  ├─ bash setup_linux.sh                              │
  ├─ bash pair_iphone.sh ──────────── USB ──────────► │ (pairing)
  ├─ bash install_sidestore.sh ─────── USB ─────────► │ (SideStore)
  └─ bash install_app.sh InMoto.ipa ── USB ─────────► │ (InMoto)
                                                       │
                                               SideStore rinnova
                                               cert ogni 7 giorni
                                               automaticamente ✓
```

---

## FASE 1 — Prepara il repository GitHub

### 1.1 Crea un account GitHub (se non ce l'hai)
Vai su https://github.com → Sign up (gratuito)

### 1.2 Crea un repository PUBBLICO
- GitHub → New repository
- Nome: `InMoto`
- **Visibilità: Public** ← obbligatorio per build gratuite
- Crea repository

### 1.3 Carica il codice
```bash
cd /home/divito-adm/InMoto
git init
git add .
git commit -m "InMoto iOS app"
git remote add origin https://github.com/TUO_USERNAME/InMoto.git
git push -u origin main
```

GitHub Actions parte automaticamente → vai su
`github.com/TUO_USERNAME/InMoto/actions` per vedere il build.

---

## FASE 2 — Firma con Codemagic (gratuito)

Codemagic firma l'IPA con il tuo Apple ID personale senza bisogno di Mac.

### 2.1 Registrati su Codemagic
- Vai su https://codemagic.io
- Sign in with GitHub

### 2.2 Aggiungi il tuo Apple ID
- Dashboard → Teams → Personal account → Integrations
- **Apple Developer Portal** → Connect
- Inserisci email e password Apple ID
- Codemagic crea automaticamente:
  - Certificato Development
  - Provisioning Profile per il tuo iPhone

### 2.3 Aggiungi l'UDID del tuo iPhone
Per poter installare una app development, Apple deve "conoscere" il tuo dispositivo.

**Trova l'UDID del tuo iPhone:**
```
iPhone → Impostazioni → Generali → Info → scorri fino a "UDID"
(tieni premuto per copiarlo)
```

In Codemagic:
- App → InMoto → Environment variables
- Aggiungi: `REGISTERED_DEVICES` = `UDID-del-tuo-iPhone`

### 2.4 Avvia il build
- Dashboard Codemagic → InMoto → Start new build
- Seleziona workflow: `ios-personal-free`
- Aspetta ~15 minuti → scarica il `.ipa` firmato

---

## FASE 3 — Prepara Linux

```bash
cd /home/divito-adm/InMoto
bash setup_linux.sh
```

Fa logout e login (per applicare le regole udev), poi riconnetti iPhone.

---

## FASE 4 — Abilita Developer Mode su iPhone

```
Impostazioni → Privacy e sicurezza → Modalità sviluppatore → Attiva
```
L'iPhone si riavvia. Conferma al riavvio.

---

## FASE 5 — Pairing iPhone ↔ Linux

```bash
# Connetti iPhone via cavo USB
# Sblocca l'iPhone
cd /home/divito-adm/InMoto
bash pair_iphone.sh
```

Quando l'iPhone mostra "Vuoi fidarti di questo computer?" → tocca **Fidati**.

---

## FASE 6 — Installa SideStore

SideStore è gratuito e open source: https://sidestore.io

### Opzione A — Via web (più semplice)
1. Apri **Safari** sull'iPhone (non Chrome, non Firefox)
2. Vai su: `https://sidestore.io`
3. Tocca **Install** → si apre la schermata di installazione OTA
4. Inserisci il tuo Apple ID quando richiesto

### Opzione B — Da Linux via USB
```bash
bash install_sidestore.sh
```

---

## FASE 7 — Configura SideStore

### 7.1 Accedi con Apple ID
- Apri SideStore sull'iPhone
- Accedi con il tuo Apple ID (stesso usato per firmare)

### 7.2 Carica il pairing file (fondamentale per il rinnovo auto)
Il pairing file permette a SideStore di rinnovarsi senza connettere il cavo.

```bash
# Da Linux, invia via AirDrop o copia con scp
# OPZIONE A: AirDrop
python3 -m pymobiledevice3 afc copy \
    ~/sidestore_pairing.mobiledevicepairing \
    /Documents/sidestore_pairing.mobiledevicepairing

# OPZIONE B: Invia via AirDrop manualmente
# Apri il file manager Linux → tasto destro → Invia via Bluetooth/AirDrop
```

In SideStore: Impostazioni → Import Pairing File → seleziona il file.

### 7.3 Attiva WireGuard
- SideStore → Impostazioni → Enable WireGuard VPN → ON
- Questo consente il rinnovo automatico senza USB

---

## FASE 8 — Installa InMoto

### Via script Linux (USB)
```bash
bash install_app.sh ~/Downloads/InMoto.ipa
```

### Via SideStore (drag & drop)
1. Trasferisci `InMoto.ipa` sull'iPhone (AirDrop, Files, ecc.)
2. Apri SideStore → tocca **+** → seleziona il file IPA
3. SideStore firma e installa

---

## FASE 9 — Configura l'app InMoto

Al primo avvio:
1. Vai in **Impostazioni** (tab in basso a destra)
2. **URL Server**: `https://indirizzo-del-tuo-server` (dove gira AMT Scanner)
3. **API Key**: il valore di `MOTO_APP_API_KEY` in `/opt/amt_scanner/.env`
4. Tocca **Sincronizza dal server**

L'app funziona anche **senza server** grazie ai 196 itinerari inclusi offline.

---

## Rinnovo (automatico con SideStore)

Con SideStore + WireGuard attivi, il certificato si rinnova **automaticamente** ogni 7 giorni in background. Non devi fare nulla.

Se per qualsiasi motivo SideStore non si rinnova automaticamente:
```bash
# Riconnetti USB e reinstalla
bash install_app.sh ~/Downloads/InMoto.ipa
```

---

## Aggiornare InMoto in futuro

Quando modifichi il codice:
```bash
cd /home/divito-adm/InMoto
git add .
git commit -m "Aggiornamento"
git push
# GitHub Actions rebuilda → Codemagic firma → scarica nuovo IPA → reinstalla
```

---

## Riepilogo costi

| Cosa | Costo |
|------|-------|
| GitHub (repo pubblico) | **Gratis** |
| Codemagic (500 min/mese) | **Gratis** |
| Apple ID personale | **Gratis** (già lo hai) |
| SideStore | **Gratis** (open source) |
| **Totale** | **€0** |
