# InMoto — Istruzioni per Claude Code

## Contesto del progetto

Sei sul **client esterno** di installazione per l'app **InMoto** — un'app iOS SwiftUI
per itinerari moto italiani. Il tuo compito è guidare l'installazione dell'app
su un iPhone 15 Pro (iOS 26) connesso via cavo USB a questa macchina Linux.

## Vincoli fondamentali

- ✅ Puoi accedere a **internet pubblico** (github.com, codemagic.io, api.codemagic.io)
- ✅ Puoi interagire con l'**iPhone via USB** (pymobiledevice3, ideviceinstaller)
- ❌ NON tentare mai di raggiungere `asr-busmanager.simongenova.local`
- ❌ NON tentare di raggiungere IP interni `172.18.x.x` o `10.90.x.x`
- ❌ NON hai bisogno di un Mac né di Xcode su questa macchina

## Struttura del progetto

```
InMoto/
├── CLAUDE.md                        ← questo file
├── project.yml                      ← configurazione XcodeGen (build su Codemagic)
├── codemagic.yaml                   ← pipeline build/firma cloud (gratuita)
├── apps.json                        ← sorgente SideStore per aggiornamenti futuri
├── setup_github.sh                  ← pubblica su GitHub (opzionale)
│
├── InMoto/                          ← codice sorgente Swift
│   ├── InMotoApp.swift
│   ├── Models/MotoRoute.swift
│   ├── Services/RouteStore.swift    ← gestione dati offline + sync
│   ├── Services/APIService.swift    ← chiamate API + AppSettings
│   ├── Views/ContentView.swift      ← tab bar principale
│   ├── Views/HomeView.swift         ← browse per regione
│   ├── Views/SearchView.swift       ← ricerca + percorso su misura
│   ├── Views/RouteDetailView.swift  ← dettaglio + Apple Maps/Google Maps
│   ├── Views/RouteCardView.swift    ← card componente
│   ├── Views/SettingsView.swift     ← URL server + API key + sync
│   └── Resources/routes.json       ← 196 itinerari offline (non serve server)
│
└── vm_install/                      ← script installazione (inizia da qui)
    ├── README_STANDALONE.md         ← requisiti e overview
    ├── README_CODEMAGIC.md          ← setup Codemagic passo passo
    ├── 1_setup_vm.sh                ← installa strumenti Linux
    ├── 2_configura.sh               ← salva credenziali Codemagic
    ├── 3_pair_e_installa.sh         ← pairing + build + installa (script principale)
    ├── 4_installa_ipa.sh            ← reinstalla/aggiorna (rinnovo 7 giorni)
    └── install_from_github.sh       ← alternativa: scarica da GitHub
```

## Workflow installazione — stato attuale

Chiedi sempre all'utente a che punto si trova. Gli step sono:

### Step 1 — Strumenti Linux
```bash
bash vm_install/1_setup_vm.sh
```
Installa: `python3`, `pymobiledevice3`, `ideviceinstaller`, `usbmuxd`, `libimobiledevice-utils`.
Non richiede internet verso server interni. **Richiede sudo.**

### Step 2 — Credenziali Codemagic
```bash
bash vm_install/2_configura.sh
```
Chiede interattivamente:
- Username GitHub
- Token API Codemagic (da `codemagic.io/teams → API token`)
- App ID Codemagic (dall'URL della app su codemagic.io)

Salva tutto in `~/.inmoto_config` (chmod 600).

**Prerequisiti Codemagic** (da fare una volta nel browser, leggi `README_CODEMAGIC.md`):
- Account gratuito su `codemagic.io`
- Apple ID collegato (con app-specific password se hai 2FA)
- UDID iPhone registrato come variabile `REGISTERED_DEVICES`

**Trovare l'UDID iPhone:**
```bash
ideviceinfo -k UniqueDeviceID
# oppure:
python3 -m pymobiledevice3 usbmux list
```

### Step 3 — Pairing + Build + Installazione
```bash
bash vm_install/3_pair_e_installa.sh
```
Questo script fa tutto in sequenza:
1. Verifica iPhone connesso via USB
2. Esegue pairing (`pymobiledevice3 usbmux pair`)
3. Avvia build su Codemagic via API
4. Attende il completamento (~15 min)
5. Scarica l'IPA firmato
6. Installa con `ideviceinstaller -i InMoto.ipa`

**Developer Mode** deve essere attivo sull'iPhone:
`Impostazioni → Privacy e sicurezza → Modalità sviluppatore → ON`

### Step 4 — Rinnovo (ogni 7 giorni)
```bash
bash vm_install/4_installa_ipa.sh
```
Ricompila e reinstalla. iPhone deve essere connesso.

---

## Diagnosi problemi comuni

### "iPhone non trovato"
```bash
sudo systemctl start usbmuxd
ideviceinfo -k ProductVersion     # verifica device riconosciuto
python3 -m pymobiledevice3 usbmux list
```
Controllare: cavo USB funzionante, iPhone sbloccato, "Fidati" toccato.

### Pairing non funziona
```bash
idevicepair unpair
idevicepair pair
# Toccare "Fidati" sull'iPhone quando appare il popup
```

### "Installazione fallita" dopo il build
Cause più comuni:
1. Developer Mode non attivo sull'iPhone
2. UDID non registrato in Codemagic (`REGISTERED_DEVICES`)
3. IPA non firmato (build fallito — controlla su codemagic.io)

Verifica stato installazione:
```bash
ideviceinstaller -l | grep InMoto
```

### Build Codemagic fallisce
- Controlla il log su `codemagic.io/build/<BUILD_ID>`
- Apple ID con 2FA: usa **app-specific password** (non la password normale)
  Genera su: `appleid.apple.com → Sicurezza → Password per le app`
- Se UDID mancante: aggiungi variabile `REGISTERED_DEVICES` in Codemagic

### pymobiledevice3 non supporta iOS 26
```bash
pip3 install --upgrade pymobiledevice3
```
La libreria si aggiorna frequentemente per supportare le nuove versioni iOS.

---

## Comandi utili rapidi

```bash
# Stato iPhone
ideviceinfo -k ProductVersion
ideviceinfo -k UniqueDeviceID

# App installate sull'iPhone
ideviceinstaller -l

# Installa IPA manualmente
ideviceinstaller -i percorso/app.ipa

# Disinstalla
ideviceinstaller -U com.divito.InMoto

# Log device in tempo reale (debug)
idevicesyslog | grep InMoto

# Verifica pymobiledevice3
python3 -m pymobiledevice3 usbmux list
```

---

## Configurazione app dopo l'installazione

Una volta installata, apri InMoto → tab **Impostazioni** e configura:

- **URL Server**: URL del server AMT Scanner
  (l'app funziona OFFLINE con 196 itinerari anche senza configurarlo)
- **API Key**: valore di `MOTO_APP_API_KEY` dal file `.env` del server

---

## Note sul codice Swift

- **Target iOS**: 17.0 minimo
- **Offline-first**: 196 itinerari in `Resources/routes.json`, caricati al primo avvio
- **Sync**: `RouteStore.syncFromServer()` chiama `/api/mobile/moto/routes` con header `X-Moto-Key`
- **Maps**: `RouteDetailView` apre Apple Maps (`MKMapItem`) o Google Maps (URL scheme)
- **Compose**: `SearchView` chiama `/api/mobile/moto/compose` per percorsi su misura

Se devi modificare il codice Swift, modifica i file in `InMoto/` e poi esegui
un nuovo build (`4_installa_ipa.sh` o riavvia il workflow Codemagic).

---

## Rinnovo automatico senza computer (SideStore)

Per evitare di rifare il rinnovo manuale ogni 7 giorni:
1. Apri **Safari** sull'iPhone → `https://sidestore.io`
2. Installa SideStore con lo stesso Apple ID
3. In SideStore → **Browse → Sources → +** → aggiungi:
   `https://raw.githubusercontent.com/TUO_USERNAME/InMoto/main/apps.json`
4. **SideStore → Impostazioni → Enable WireGuard → ON**

Da questo momento SideStore rinnova il certificato ogni 7 giorni in automatico.
