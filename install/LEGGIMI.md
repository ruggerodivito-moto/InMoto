# InMoto — Installazione su iPhone

## Cosa ti serve

| Cosa | Come ottenerlo | Costo |
|------|----------------|-------|
| Account GitHub | github.com → Sign up | Gratis |
| Apple ID | Già lo hai | Gratis |
| Codemagic | codemagic.io → Sign in with GitHub | Gratis (500 min/mese) |
| SideStore | sidestore.io da iPhone Safari | Gratis |

---

## Step 1 — Prima volta: pubblica il codice su GitHub

Fai questo UNA VOLTA SOLA dal server Linux:

```bash
cd /home/divito-adm/InMoto

# Sostituisci TUO_USERNAME con il tuo username GitHub
bash setup_github.sh TUO_USERNAME
```

Questo script:
- Inizializza il repository git
- Sostituisce `ruggerodivito-moto` con il tuo username in tutti i file
- Crea il repository su GitHub (via GitHub CLI) o ti dà le istruzioni manuali
- Fa il primo push → GitHub Actions parte automaticamente

---

## Step 2 — Firma con Codemagic (prima volta)

1. Vai su **https://codemagic.io** → Sign in with GitHub
2. Clicca **Add application** → seleziona il repository `InMoto`
3. **Teams → Personal account → Integrations → Apple Developer Portal → Connect**
   - Inserisci email Apple ID + password
   - Se hai la verifica in due passi: genera una App-specific password su
     **appleid.apple.com → Sicurezza → Password per le app**
4. Trova il tuo **UDID iPhone** (necessario per firmare):
   - iPhone → Impostazioni → Generali → Info → scorri fino a "UDID" → tieni premuto → Copia
5. In Codemagic → InMoto → **Environment variables** → aggiungi:
   - Nome: `REGISTERED_DEVICES` → Valore: `il-tuo-UDID`
6. Clicca **Start new build** → seleziona `ios-personal-free`
7. Aspetta ~15-20 minuti → comparirà il file `InMoto.ipa` da scaricare

---

## Step 3 — Installa l'app sull'iPhone

### Da Windows (consigliato)
Scarica la cartella `install/windows/` e fai doppio clic su `installa.bat`

Lo script fa tutto automaticamente:
- Scarica l'IPA da GitHub Releases
- Installa Sideloadly se non presente
- Apre Sideloadly con l'IPA pronto

Connetti iPhone, inserisci Apple ID in Sideloadly → **Start** → fatto.

### Da Mac
Scarica `install/mac/installa.command` e aprilo (doppio click).

Scegli AltStore (migliore) o Sideloadly e segui le istruzioni.

---

## Step 4 — SideStore (rinnovo automatico, una volta sola)

Dopo aver installato InMoto, configura SideStore per il rinnovo automatico:

1. Apri **Safari** sull'iPhone → vai su `https://sidestore.io`
2. Segui le istruzioni di installazione di SideStore
3. Apri SideStore → accedi con lo **stesso Apple ID** usato in Codemagic
4. Vai in **Browse → Sources → +** → incolla l'URL della sorgente:
   ```
   https://raw.githubusercontent.com/TUO_USERNAME/InMoto/main/apps.json
   ```
5. Installa InMoto da SideStore (sostituisce la versione installata prima)
6. **SideStore → Impostazioni → Enable WireGuard → ON**

Da ora SideStore rinnova il certificato ogni 7 giorni automaticamente.
Ogni nuovo push al repository produrrà una nuova versione installabile
direttamente da SideStore senza toccare il computer.

---

## Come aggiornare InMoto in futuro

```bash
# Sul server Linux, dopo aver modificato il codice:
cd /home/divito-adm/InMoto
git add .
git commit -m "Aggiornamento"
git push
```

GitHub Actions rebuilda → la nuova versione compare in SideStore → tocca **Update**.

---

## Configura l'app al primo avvio

1. Apri InMoto → tab **Impostazioni** (icona ingranaggio)
2. **URL Server**: `https://indirizzo-del-tuo-server`
   (es. `https://amt-scanner.tuodominio.it`)
3. **API Key**: il valore di `MOTO_APP_API_KEY` in `/opt/amt_scanner/.env`
   ```bash
   grep MOTO_APP_API_KEY /opt/amt_scanner/.env
   ```
4. Tocca **Sincronizza dal server**

L'app funziona anche **senza server** con i 196 itinerari offline.
