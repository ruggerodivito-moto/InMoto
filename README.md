# InMoto — App iOS per itinerari moto

App SwiftUI nativa per iPhone che replica il servizio "In Moto" del server AMT Scanner.

## Funzionalità
- **196 itinerari** italiani pre-caricati (offline, no internet)
- **Browsing per regione** — tutte le 20 regioni italiane
- **Ricerca avanzata** — partenza, arrivo, km, durata
- **Percorso su misura** — composizione dinamica dal server
- **Apple Maps + Google Maps** — apertura diretta con tutte le tappe
- **Aggiunta tappe** — personalizza il percorso prima di aprirlo
- **Sync dal server** — aggiorna gli itinerari quando online

---

## Struttura progetto

```
InMoto/
├── project.yml              ← XcodeGen: genera il .xcodeproj
├── codemagic.yaml           ← Build cloud con Codemagic
├── .github/workflows/       ← Build alternativa con GitHub Actions
└── InMoto/
    ├── InMotoApp.swift
    ├── Models/
    │   └── MotoRoute.swift
    ├── Services/
    │   ├── RouteStore.swift
    │   └── APIService.swift
    ├── Views/
    │   ├── ContentView.swift
    │   ├── HomeView.swift
    │   ├── RouteCardView.swift
    │   ├── RouteDetailView.swift
    │   ├── SearchView.swift
    │   └── SettingsView.swift
    └── Resources/
        └── routes.json      ← 196 itinerari bundled
```

---

## Cosa ti serve

| Cosa | Costo | Note |
|------|-------|------|
| Account [Codemagic](https://codemagic.io) | Gratis (500 min/mese) | Per compilare l'app senza Mac |
| [Apple Developer Program](https://developer.apple.com/programs/) | 99€/anno | Per installare su iPhone |
| Repository GitHub/GitLab | Gratis | Per il codice sorgente |

---

## Step 1 — Crea il repository

```bash
cd /home/divito-adm/InMoto
git init
git add .
git commit -m "Initial InMoto iOS project"
# Crea un repo su GitHub e aggiungi il remote:
git remote add origin https://github.com/TUO_USERNAME/InMoto.git
git push -u origin main
```

---

## Step 2 — Apple Developer account

1. Vai su https://developer.apple.com/account
2. Crea un **App ID**: `com.divito.InMoto`
3. Crea un **Development Certificate** (o Distribution per TestFlight)
4. Crea un **Provisioning Profile** per il tuo iPhone
5. Scarica il certificato `.p12` e il profilo `.mobileprovision`

---

## Step 3 — Configura Codemagic

1. Vai su https://codemagic.io → Sign in con GitHub
2. Aggiungi il repository
3. Vai in **Environment variables** e aggiungi:
   - `CERTIFICATES_P12` → contenuto del .p12 in base64: `base64 -w 0 cert.p12`
   - `CERTIFICATES_PASSWORD` → password del .p12
   - `PROVISIONING_PROFILE` → contenuto del .mobileprovision in base64
   - `APPLE_TEAM_ID` → il tuo Team ID (es. `ABC123DEF4`)
4. In `project.yml` imposta il tuo `DEVELOPMENT_TEAM`
5. Avvia il primo build → scarica il `.ipa`

---

## Step 4 — Installa sull'iPhone

**Opzione A — TestFlight** (più semplice):
- Carica il `.ipa` su App Store Connect → TestFlight
- Installa TestFlight sul tuo iPhone
- Accetta l'invito → installa l'app

**Opzione B — AltStore** (gratuito, richiede rinnovo ogni 7 giorni senza account):
- Installa [AltServer](https://altstore.io) su un PC Windows o Mac
- Installa AltStore sull'iPhone via AltServer
- Trascina il `.ipa` su AltStore → installa

---

## Step 5 — Configura l'app

Al primo avvio, vai in **Impostazioni** e inserisci:
- **URL Server**: `https://TUO-SERVER-NGINX` (l'URL del server AMT Scanner)
- **API Key**: il valore di `MOTO_APP_API_KEY` nel file `/opt/amt_scanner/.env`

Poi premi **Sincronizza dal server** per aggiornare gli itinerari.

L'app funziona **offline** con i 196 itinerari pre-caricati anche senza configurare il server.

---

## API Key

Il server AMT Scanner espone queste API per l'app mobile:
```
GET  /api/mobile/moto/routes    ← lista itinerari (con filtri)
GET  /api/mobile/moto/regions   ← lista regioni
POST /api/mobile/moto/compose   ← genera percorso su misura
```
Tutte richiedono l'header: `X-Moto-Key: <MOTO_APP_API_KEY>`

---

## Nota sui km/durata nei percorsi su misura

I valori di km e durata per i percorsi generati dinamicamente sono **stime** basate sul numero di tappe. La stima reale la fornisce Google Maps/Apple Maps quando apri il percorso.
