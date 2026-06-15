# InMoto — Istruzioni per Claude Code

App **iOS SwiftUI** per itinerari e viaggi moto. Questo repository contiene il
codice sorgente Swift, la pipeline di build cloud e gli script di installazione.
Si sviluppa **senza Mac e senza Xcode locale**: la compilazione avviene su GitHub
Actions, la firma e l'installazione sull'iPhone con Sideloadly su Windows.

> ⚠️ La storica documentazione "client Linux + Codemagic + pymobiledevice3 install"
> è **obsoleta**. La pipeline reale è quella descritta qui sotto.

---

## Ambiente reale

- **Host**: Windows 11, shell PowerShell (più Bash/Git-Bash per script POSIX).
- **Build**: GitHub Actions (`.github/workflows/release.yml`) compila l'IPA **non
  firmato** su `macos-15`. È l'unico check di compilazione Swift — niente
  `swiftc`/Xcode in locale, quindi un errore Swift si scopre solo qui.
- **Firma + installazione**: **Sideloadly** (GUI) firma con l'Apple ID e installa
  via USB. Non si può passare l'IPA da riga di comando.
- **iPhone**: iPhone 15 Pro, iOS 26.x, collegato via USB, pairing già fatto.
- **Python per gli strumenti device**: usare sempre **`py -3.12`** (il 3.14 di
  default non compila pymobiledevice3).

### Fatti fissi del progetto

- Repo GitHub: `ruggerodivito-moto/InMoto`, branch `main`.
- Bundle id installato (suffisso team Sideloadly): `com.divito.InMoto.3S34FCRGM2`.
  (Il bundle id "base" nel `project.yml` è `com.divito.InMoto`.)
- UDID iPhone: `00008130-00022C8E0A51001C`.
- Cartella download IPA: `C:\Users\divito_adm\Downloads\`.
- Versione: `CFBundleShortVersionString` = `1.0.<data>` (es. `1.0.20260612`),
  `CFBundleVersion` = numero di build incrementale (il `<run>` del tag). Entrambi
  sono scritti dalla pipeline in `project.yml` durante il build.

---

## Rilascio di una nuova versione — usa la skill `fine_creazione_ipa`

Ogni volta che modifichi il codice Swift e vuoi portarlo sul telefono, esegui la
skill **`/fine_creazione_ipa`** (in `.claude/skills/fine_creazione_ipa`). In sintesi:

1. **Commit** dei soli file modificati.
2. **`git pull --rebase origin main`** poi **`git push`** (il bot di rilascio
   committa `chore: release … [skip ci]` dopo ogni build, quindi senza rebase il
   push viene rifiutato). Prendi lo **SHA reale** con `git rev-parse HEAD`, mai inventarlo.
3. **Attendi** il workflow "Build & Release IPA" finché `completed|success`,
   pollando le run per quello SHA. Se `failure`, leggi il log su GitHub Actions.
4. **Scarica** entrambi gli asset della release in `Downloads/`:
   `InMoto-<tag>.ipa` (versionato, per l'utente) e `InMoto.ipa` (nome stabile).
   Verifica che la dimensione coincida con l'asset.
5. **Installazione manuale** con Sideloadly: chiedi all'utente di **riselezionare**
   l'IPA versionato nella GUI, Apple ID + iPhone collegato e sbloccato, **Start**,
   password/2FA. Se si blocca su "Preparing Anisette 50%": killare `sideloadly` +
   `sideloadlydaemon`, riaprire e ripetere. Aspetta che confermi "fatto".
6. **Verifica** la `CFBundleVersion` installata = numero di build atteso:
   ```bash
   py -3.12 -m pymobiledevice3 apps query com.divito.InMoto.3S34FCRGM2 2>&1 \
     | python -c "import sys,json; d=json.load(sys.stdin); v=list(d.values())[0]; print(v.get('CFBundleVersion','?'))"
   ```

⚠️ Caveat PowerShell: messaggi di commit con `" / "` (spazio-slash-spazio) possono
far scattare un blocco di sicurezza fasullo. Riformula senza ` / `.

---

## Architettura dell'app

Entry point `InMotoApp.swift`: inietta tre `@EnvironmentObject` →
`RouteStore` (dati), `AppSettings.shared` (config server), `AppState`
(`selectedTab`). `store.loadInitial()` carica i 196 itinerari offline al primo avvio.

### Modelli (`InMoto/Models/`)
- `MotoRoute.swift` — itinerario/tragitto (anche personale, `isCustom`).
- `TripPlan.swift` — **viaggio a tappe (roadbook)**: `items: [TripPlanItem]`
  (`.tappa` / `.pausa` / `.arrivo`), orari, km/durata, nota finale.
  `motoRoute(for:)` produce una `MotoRoute` navigabile per ogni tappa.
- `NavigationModels.swift` — `GeocodedWaypoint`, `RouteLeg`, `RouteStep`,
  `NavigationRoute`, `TurnDirection`, `FavoritePlace`.

### Servizi (`InMoto/Services/`)
- `RouteStore.swift` — persistenza offline: `routes`, `personalRoutes`,
  `tripPlans`, `favoritePlaces`; salva/elimina/**rinomina** viaggi; sync dal server.
- `RouterService.swift` — geocoding (anche coord "lat,lon"), `computeLegs` via
  `MKDirections`, `connectorLeg` (posizione attuale → tappa), cache percorsi/tratte.
- `NavigationSession.swift` — sessione di navigazione attiva: map-matching su
  `RouteGeometry`, avanzamento automatico tra le tappe, annunci vocali (con
  `isMuted` persistito), ricalcolo fuori percorso.
- `RouteGeometry.swift` — geometria/progressione in metri lungo il percorso.
- `LocationManager.swift` — GPS singleton; `start/stop`, `requestOneShot` (un solo
  fix senza navigazione continua).
- `RoadbookParser.swift` — interpreta il testo di un roadbook in un `TripPlan`
  (sezioni `TAPPA n` / `PAUSA n` / `ARRIVO`, orari, km/durata, note tra parentesi,
  link Google Maps). Il formato è documentato nel commento in cima al file.
- `AddressCompleter.swift` — suggerimenti indirizzi (Apple Maps).
- `APIService.swift` — `AppSettings` + chiamate API mobile.

### Viste (`InMoto/Views/`)
- `ContentView.swift` — **TabView a 2 tab**:
  - **tab 0 "Bikers Liguria Roadtrip"** → `ImportedRoutesView` (viaggi/tragitti
    personali; il `+` importa link, roadbook o compone viaggi).
  - **tab 1 "Altro"** → `MoreView`.
- `MoreView.swift` — lista che raccoglie: **"Viaggi Personali"** (`HomeView`,
  browser dei 196 itinerari per regione), **"Luoghi preferiti"**
  (`FavoritePlacesView`), **Guida "Come aggiungere un viaggio"** (`GuideView`),
  **"Impostazioni"** (`SettingsView`). Queste viste **non** hanno un proprio
  `NavigationStack` (lo fornisce `MoreView`); `ImportedRoutesView` e `HomeView`
  invece lo hanno quando sono il tab principale.
- `TripPlanViews.swift` — dettaglio viaggio e import roadbook:
  - `TripPlanDetailView` — timeline; ogni riga è navigabile (tappa → percorso su
    mappa + navigazione; pausa/arrivo → posizione su mappa).
  - `TripStageDetailView` — anteprima percorso tappa (`StageMapPreview`), punti di
    passaggio, avvio navigazione. **Se sei lontano (>300 m) dal primo punto, chiede
    se anteporre la posizione attuale** come partenza.
  - `TripPlaceView` — posizione di una pausa/arrivo con apertura in Apple/Google Maps.
  - `RoadbookImportView` — incolla testo → "Analizza" → anteprima con **campo
    "Nome del viaggio" modificabile** → "Salva viaggio".
- `NavigatorView.swift` — navigazione a tutto schermo: barra riepilogo
  (tappa/ETA/rimanente) **in alto** sopra le indicazioni, pulsante **muta voce**
  in toolbar, avvio GPS, ricentra.
- `MapKitView.swift` — mappa di navigazione: percorso fatto/futuro, pin tappe/
  svolte, **icona moto**, camera **course-up** (direzione di marcia sempre verso
  l'alto), lookahead in marcia.
- `DownloadPreparationView.swift` — `DownloadPreparationViewModel` (geocoding +
  routing + cache) usato per preparare i percorsi.
- Altre: `HomeView` (browser regioni), `RouteDetailView`, `RouteCardView`,
  `SearchView`, `CreateRouteView`, `ComposeTripView`, `FavoritePlacesView`,
  `SettingsView` (la **Versione** è letta da `CFBundleShortVersionString` +
  `CFBundleVersion`, non hardcoded).

> Nota: `SearchView` e `CreateRouteView` esistono ancora ma **non** sono nei tab
> (rimossi "al momento" dalla barra). Si possono riattaccare se servono.

---

## Build config

`project.yml` (XcodeGen, eseguito in CI): sorgenti = tutta la cartella `InMoto/`
(esclusi i `.md`), quindi **i nuovi file Swift vengono inclusi automaticamente**.
Target iOS 17.0. La pipeline scrive versione/build dentro `project.yml` prima di
generare il progetto e builda l'`Info.plist` da lì.

---

## Diagnosi rapida

| Problema | Causa / fix |
|---|---|
| push rifiutato (`rejected`) | manca il rebase → `git pull --rebase origin main` |
| build `failure` | leggi il log del run su GitHub Actions (unico check Swift) |
| `apps query` dà JSON vuoto/errore | iPhone scollegato o bloccato; riconnetti e sblocca |
| versione installata non cambia | Sideloadly non ha completato; riseleziona IPA e Start |
| pymobiledevice3 non parte | usa `py -3.12`, non `py`/`python` |
| Sideloadly fermo a "Preparing Anisette 50%" | killa `sideloadly`+`sideloadlydaemon`, riapri |

### Comandi utili
```bash
# Stato Sideloadly (PowerShell)
Get-Process sideloadly,sideloadlydaemon

# Versione installata sull'iPhone
py -3.12 -m pymobiledevice3 apps query com.divito.InMoto.3S34FCRGM2

# Strumenti device
py -3.12 -m pymobiledevice3 usbmux list
```

---

## Configurazione app (opzionale)

L'app funziona **offline** con 196 itinerari. Per la sync dal server: tab
**Altro → Impostazioni** → URL server AMT Scanner + API Key (`MOTO_APP_API_KEY`
dal `.env` del server). `RouteStore.syncFromServer()` chiama
`/api/mobile/moto/routes` con header `X-Moto-Key`.

---

## 🔐 TODO Sicurezza iOS — da affrontare (analisi 2026-06-13)

Audit della versione iOS rilasciata `1.0.20260612` (build 32). Superficie ridotta
(offline-first, niente login/WebView/deep-link/SQL); i rischi sono su **storage
locale** e **gestione credenziali**. Da implementare (poi un giro di
`/fine_creazione_ipa`):

**🟠 Medi — priorità**
1. **API key in chiaro in `UserDefaults` → spostare in Keychain.**
   `APIService.swift:38-40,50`: `apiKey` (la `MOTO_APP_API_KEY`) è scritta in
   `UserDefaults`, leggibile da backup iTunes/Finder non cifrato e su jailbreak.
   Usare Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). `serverURL`
   può restare in UserDefaults.
2. **Dati personali su disco senza file-protection esplicita.**
   `RouteStore.swift` (personal_routes/trip_plans/**favorite_places**) e cache nav
   in `RouterService.swift`: i `FavoritePlace` contengono indirizzi tipo "Casa"
   (dato di posizione). Aggiungere `options: [.atomic, .completeFileProtection]`
   alle `write(to:)` dei dati personali.

**🟡 Minori**
3. **Force-unwrap su URL da input utente → crash.** `APIService.swift:45`
   `URL(string: serverURL + path)!`: un `serverURL` malformato crasha la sync.
   Usare `guard let`/`URLComponents`.
4. **`GoogleMapsParser.resolveShortURL` fa GET su URL arbitrario senza validare
   il dominio** (`ImportedRoutesView.swift:709-720`): limitare a host
   Google Maps prima e dopo il redirect.
5. **Nessun certificate pinning sulla sync** (`RouteStore.swift:203`,
   `URLSession.shared`): la `X-Moto-Key` è su HTTPS (ATS di default attivo, ok),
   pinning solo se serve irrigidire il modello di minaccia.

**✅ Già corretto (non toccare):** ATS non indebolito (niente
`NSAppTransportSecurity` in `project.yml` → HTTPS obbligatorio); validazione
range lat/lon in `geocodeMixed`; percent-encoding dei waypoint negli URL esterni;
permessi location dichiarati/motivati; solo `JSONDecoder` su Codable (niente
unarchiver insicuro).

> ⚠️ La stessa logica (`AppSettings`/UserDefaults, parser link, storage JSON) è
> portata 1:1 su **Android** (`android/`): #1, #2 e #4 si ripresentano lì.

---

## 🟢 PROGETTO IN CORSO — Versione Android (`android/`)

Versione Android dell'app, in sviluppo nella cartella **`android/`** dello stesso
repo. **Decisioni prese** (sessione 2026-06-12):

1. **Tecnologia** → **Kotlin + Jetpack Compose** (nativa; l'app iOS resta intatta).
2. **Scope v1** → **parità completa**, incluso il navigatore live.
3. **Provider mappe** → **MapLibre/OSM** + routing **OSRM pubblico** (nessuna API key).
4. **Build** → **GitHub Actions → APK debug** (workflow Android dedicato).

> ✅ L'utente **ha un dispositivo Android** su cui testare l'APK (installazione
> diretta dell'APK debug, niente firma/sideload come iOS).

### Stato avanzamento (aggiornato 2026-06-12)

**Fatto e committato/pushato** (commit `9fcb564` su main):
- Scaffold Gradle in `android/` (AGP 8.7.3, Kotlin 2.0.21, Compose BOM 2024.10.01,
  minSdk 26, compileSdk 35, package `com.divito.inmoto`).
- Modelli Kotlin (`model/`): `MotoRoute`, `TripPlan`/`TripPlanItem`,
  `GeocodedWaypoint`/`RouteLeg`/`RouteStep`/`NavigationRoute`, `FavoritePlace`,
  `TurnDirection`, `GeoPoint` — kotlinx.serialization.
- `routes.json` (196 itinerari) copiato in `app/src/main/assets/`.
- `data/`: `RouteRepository` (port di RouteStore: offline + personali + viaggi +
  preferiti + filtro/compose/sync), `RoadbookParser` + `GoogleMapsParser` (port 1:1),
  `RouterService` (geocoding **Nominatim** + routing **OSRM** + cache tratte/percorsi),
  `Http`, `AppSettings`, `Json`.
- UI Compose (`ui/`): root 2 tab (`MainActivity` + Navigation Compose),
  schermate Roadtrip, Altro, browser regioni, dettagli itinerario/viaggio/tappa,
  import roadbook, componi viaggio, preferiti, impostazioni, guida, navigatore base.
- CI: `.github/workflows/android.yml` (APK debug su push `android/**`, pubblica
  release `android-v…`). Il workflow iOS `release.yml` ora ha `paths-ignore` per
  `android/**`, `**.md`, `.github/workflows/**` (così le modifiche Android non
  rebuildano l'IPA).

**Fatto dalla ripresa (sessione 2026-06-12, build Android verde)**:
- ✅ Fix `computeLegs` (`continue` dentro lambda → `if`), commit `29a5182`.
- ✅ `build.yml` ("iOS Build") ora ha lo stesso `paths-ignore` di `release.yml`
  (commit `657fa68`): i commit solo-Android/md non rebuildano più l'iOS.
- ✅ **Mappe MapLibre** (task 7, commit `7f5ad77`): dipendenza
  `org.maplibre.gl:android-sdk:11.8.5` (Maven Central, no API key). Nuovo
  `ui/components/RouteMap.kt` = `MapView` MapLibre con lifecycle, stile **raster
  OSM inline** (tile `tile.openstreetmap.org`), polyline (`LineLayer`) + pin
  waypoint (`CircleLayer`), camera fit-to-bounds. `RoutePreviewMap` ora prende
  una `MotoRoute` + `vm`, costruisce la `NavigationRoute` (cache) e disegna la
  mappa (placeholder durante il caricamento). `NavigatorScreen` usa `RouteMap`
  diretto. ⏳ Da verificare a vista sul dispositivo (tile/pin/polyline).
  Package MapLibre 11.x: `org.maplibre.android.*`, geojson `org.maplibre.geojson.*`.

- ✅ **Navigazione live — logica** (task 8a, commit `9bc5b82`, build Android
  partita; **conferma esito CI alla ripresa**: era in corso quando ci siamo
  fermati). Tre file nuovi in `data/`, ancora **NON agganciati alla UI**:
  - `RouteGeometry.kt` — port 1:1 di `RouteGeometry.swift`: polyline appiattito
    con distanze progressive, `match()` (map-matching con finestra attorno
    all'ultimo aggancio + ricerca in avanti), `legIndex`, `upcomingStepIndex`,
    `bearingAtProgress` (per camera course-up), `distance`/`bearing` (Haversine).
  - `LocationProvider.kt` — `FusedLocationProviderClient` esposto come
    `Flow<Location>` via `callbackFlow` (HIGH_ACCURACY ~1 s/5 m, scarta fix >100 m).
    Il **permesso runtime** lo deve richiedere il chiamante prima di collezionare.
  - `NavigationSession.kt` — port di `NavigationSession.swift`: avanzamento
    tappe/manovre dalla progressione in metri, annunci **TTS italiano**
    (`android.speech.tts.TextToSpeech`, `Locale.ITALIAN`) basati sul tempo alla
    manovra, **ricalcolo fuori percorso** (>70 m × 3 fix → `connectorLeg`),
    arrivo automatico, mute. Espone `StateFlow<NavState>` (snapshot immutabile
    con tutti i valori per la UI: istruzione, ETA, rimanente, `matched`+`course`
    per moto/camera, `upcomingTurns`, ecc.). Costruttore:
    `NavigationSession(context, scope, initial: NavigationRoute, muted)`.

- ✅ Build CI di `9bc5b82` (task 8a) confermata `success`.

- ✅ **Navigazione live — UI** (task 8b, commit `f631172`, build Android
  `success`). Due file:
  - `ui/screens/NavigatorScreen.kt` **riscritto** da lista-manovre a navigazione
    live a tutto schermo. `LiveNavigation`: crea `NavigationSession`
    (`rememberCoroutineScope`), `remember` di `LocationProvider`, `collectAsState`
    su `session.state`; richiesta permesso `ACCESS_FINE_LOCATION` con
    `rememberLauncherForActivityResult(RequestPermission())`; `LaunchedEffect`
    che colleziona `locationUpdates()` → `session.onLocation`; `DisposableEffect`
    → `session.shutdown()`. `ManeuverCard` in alto = back + icona direzione
    (`maneuverIcon()` map `TurnDirection`→Material extended) + `currentInstruction`
    + distanza al prossimo step, riga riepilogo (`progressText`/`etaCurrentLeg`/
    `remainingFormatted`/`nextWaypointName`), avviso reroute/fuori-percorso.
    FAB **ricentra** (solo se `follow=false`) + **muta voce** (`session.setMuted`).
    `BottomStatus`: chip GPS in attesa / arrivo / permesso negato (→ Apri in Maps).
  - `ui/components/NavigationMap.kt` **nuovo** (NON riusa `RouteMap`): MapLibre/OSM
    con **camera course-up** (`CameraPosition` target=matched, bearing=course,
    tilt 45, zoom 16.5, `animateCamera` 700 ms a ogni fix), follow disattivato sul
    drag utente (`addOnCameraMoveStartedListener` REASON_API_GESTURE → `onUserPan`).
    Icona moto = `SymbolLayer` con bitmap chevron generata a runtime,
    `iconRotate(Expression.get("bearing"))` + `iconRotationAlignment=MAP` (resta
    verso l'alto). Polyline ridisegnata su `routeVersion` (cambia al reroute).
    `MapsLauncher.openRoute` resta il fallback "Apri in Google Maps".
  - ⏳ **Da verificare a vista sul dispositivo**: tile/polyline/icona moto, camera
    course-up in marcia, annunci TTS, ricalcolo fuori percorso. Gotcha risolto in
    CI: `by rememberUpdatedState(...)` richiede `import androidx.compose.runtime.getValue`.

**Sessione 2026-06-14 — test su device + fix geocoding (DOVE SIAMO)**:
- ✅ **adb installato** in `C:\Users\divito_adm\AppData\Local\Android\Sdk\platform-tools\`
  (platform-tools standalone, aggiunto al PATH utente). Device autorizzato:
  **Samsung Galaxy Tab S9 FE+** (`SM-X716B`, Android 16, serial `R52X901XGWK`).
  Pacchetto installato = `com.divito.inmoto.debug` (suffisso `.debug`!), versione
  letta con `adb shell dumpsys package com.divito.inmoto.debug | grep version`.
  Installazione: `adb install -r <apk>`. Dati app estraibili con
  `adb exec-out run-as com.divito.inmoto.debug cat files/trip_plans.json`.
- 🐞 **Bug trovato**: aprendo una tappa di un viaggio importato → errore
  "Impossibile localizzare …". Causa: i waypoint erano salvati come **testo
  verboso** (es. `Autogrill, Autostrada, A6 Torino - Savona, KM 18, 17043
  Carcare SV`); il geocoder **Nominatim** su quelle stringhe (e sulle tappe in
  Francia) restituisce `[]` → `RouterException`. Su iOS non si vede perché
  CLGeocoder (Apple) è molto più tollerante. Il messaggio nasce in
  `RouterService.kt:66-72`. **Non semplificare gli indirizzi**: rischio strada
  sbagliata (richiesta esplicita dell'utente).
- ✅ **Fix applicato** (commit `9f5f5f2`, build Android **#8 success**):
  `GoogleMapsParser.kt` ora per i link `/dir/` estrae le **coordinate esatte**
  dei waypoint dal parametro `data=` (coppie `!2m2!1d<lon>!2d<lat>`, regex
  `dirCoordRegex`) e le usa come waypoint in formato `lat,lon` (priorità sui
  nomi, che restano solo etichetta). Così si segue **esattamente** il tracciato
  Google senza geocoding. Verificato sul link reale dell'utente
  (`maps.app.goo.gl/YtqmXAupx7LXos2i9` → 3 coord giuste → OSRM 147.7 km ≈ i
  148 km del roadbook). Lo short link si risolve con
  `curl.exe -s -L -o NUL -w "%{url_effective}" <short>` (PowerShell 5.1
  `Invoke-WebRequest -MaximumRedirection 0` dà errore di stato).
- ✅ **APK V8 già scaricato e installato sul tablet**
  (`C:\Users\divito_adm\inmoto\InMotoAndroid_V8.apk`, versione installata
  `1.0.20260614.8` / versionCode 8). ⚠️ La CI firma ogni build con una chiave
  debug **diversa** → `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: serve
  `adb uninstall com.divito.inmoto.debug` prima di `adb install`. La disinstalla
  ha **azzerato i dati** dell'app (il viaggio "Viaggio test" non c'è più).
  **➡️ RISOLTO dalla sessione 2026-06-15 (keystore debug fissa): da V11 in poi
  gli aggiornamenti si installano con `adb install -r` senza disinstallare.**
- ⏳ **DA FARE alla ripresa = SOLO I TEST** (in ordine):
  1. Aprire l'app sul tablet.
  2. **RE-IMPORTARE il roadbook**: tab *Bikers Liguria Roadtrip* → `+` →
     "Importa roadbook (viaggio)" → incollare il testo → Analizza → Salva.
     (Indispensabile: i dati erano azzerati e comunque solo il re-import
     rigenera i waypoint con le coordinate dal fix.)
  3. Aprire la Tappa 1 → la mappa deve caricare percorso/punti **senza** l'errore
     "Impossibile localizzare".
  4. Verifica navigazione live (tile/polyline/icona moto, camera course-up,
     TTS italiano, ricalcolo fuori percorso) — vedi ⏳ più sopra. Per i log
     durante il test: `adb logcat` (l'app NON logga gli errori di rete, sono solo
     a UI; per ispezionare i dati salvati usare `adb exec-out run-as … cat …`).

**Sessione 2026-06-15 — icona, fix GPS, keystore fissa (DOVE SIAMO)**:
- ✅ **Icona app = stessa dell'iOS** (commit `86391b9`, build #9). Nuovo
  `tools/genera_icona_android.py`: genera dallo stesso `tools/Logo_Bikers.jpeg`
  le mipmap legacy quadrate + il foreground adaptive (logo nella safe zone,
  sfondo `#202020`). Sostituito il segnaposto vettoriale; `mipmap-anydpi-v26`
  punta a `@mipmap/ic_launcher_foreground`. Rimosso `HANDOFF_OPUS.md` (obsoleto).
- ✅ **Fix "In attesa del GPS"** (commit `ff58ebc`, build #10). `LocationProvider.kt`:
  con `PRIORITY_HIGH_ACCURACY` il FusedLocationProvider aspettava il lock GPS e
  `setMinUpdateDistanceMeters(5f)` sopprimeva gli update **da fermo** → nessun fix
  arrivava, `matched` restava null, chip bloccato (e niente reroute). Ora: **seed
  immediato** (`lastLocation` + `getCurrentLocation`), niente filtro distanza,
  soglia accuracy 150 m. Diagnosi fatta con `adb logcat` (GPS non aggancia al
  chiuso, ma esiste un fix di rete a 14 m mai consegnato allo stream).
- ✅ **Keystore debug fissa** (commit `c8cdb20`, build #11). `android/app/debug.keystore`
  committata + `signingConfigs.debug` in `app/build.gradle.kts` (cred. standard
  `android`/`androiddebugkey`/`android`). Fine del data-wipe a ogni update.
  **APK V11 installato** (`1.0.20260615.11`, signature `fd3bc305`).
- ⏳ **DA FARE = TEST live** (dati azzerati nell'ultima transizione di chiave):
  re-importare il roadbook, aprire Tappa 1, avviare navigazione → il chip
  "In attesa del GPS" deve sparire in pochi secondi. Da casa (lontano dal
  percorso) parte il reroute verso la partenza: è corretto; il test vero della
  navigazione si fa in strada.

**Altri possibili prossimi passi (Android)**:
- Opz.: foreground service di localizzazione per schermo spento (in moto). Per
  v1 va bene foreground a schermo acceso.
- Pass generale di parità UI con iOS / rifiniture.

**Note pipeline Android / CI**:
- `gh` CLI **non** è installato. Per leggere i log di una run: API REST GitHub
  `https://api.github.com/repos/ruggerodivito-moto/InMoto/actions/runs?head_sha=<SHA>`;
  per i log servono auth — il token sta nel credential manager, recuperabile con
  `git credential fill` alimentato via `Start-Process git -RedirectStandardInput
  <file>` (il pipe diretto dà exit 128; **non** usare `cmd /c "... < file"`: il
  filtro PowerShell blocca `/c`). Poi `Invoke-WebRequest .../logs` con
  `Authorization: token <PAT>`, estrai lo zip e cerca le righe `e: file://…` /
  `.kt:` per gli errori Kotlin.
- L'unico check di compilazione Kotlin è la build CI (come per iOS): niente SDK
  Android in locale. Attenzione ricorrente: Kotlin **vieta** `break`/`continue`
  dentro lambda inline (`let`/`also`/`forEach`) — usare `if`/`for` espliciti.
- ✅ L'utente **ha un dispositivo Android** per provare l'APK: l'APK debug
  prodotto dalla CI si installa diretto (abilitare "origini sconosciute").

**Naming e download dell'APK** (commit `be73c63`):
- Il workflow `android.yml` pubblica nella release `android-v<versione>-<build>`
  **due** asset: `InMotoAndroid_V<build>.apk` (versionato) e `InMoto-android.apk`
  (nome stabile = ultimo). `<build>` = `github.run_number` = `versionCode`
  incrementale: **più alto = più recente**. Sul device la versione mostrata è
  `versionName` = `1.0.<data>.<build>` (es. `1.0.20260613.7`): per sapere se hai
  l'ultima, confronta il numero finale con il `V<build>` del file.
- **Download nella cartella del progetto** (`C:\Users\divito_adm\InMoto\`), nome
  `InMotoAndroid_V<build>.apk`. Gli `.apk` sono in `.gitignore` (non si committano).
  Per scaricarlo: prendi l'URL dell'asset dalla release tag corrispondente e
  `Invoke-WebRequest -OutFile` (file ~62 MB), poi verifica che la dimensione
  coincida con l'asset.
- `.gitignore` ora esclude `*.apk` e `sideloadlydaemon.log`; `.gitignore` è stato
  aggiunto al `paths-ignore` dei workflow iOS (`build.yml`, `release.yml`) così una
  sua modifica non rebuilda l'IPA.
- **Perché l'APK (~62 MB) è molto più grosso dell'IPA**: porta dentro il motore
  mappe **MapLibre nativo** (librerie `.so` per tutte le ABI: arm64-v8a,
  armeabi-v7a, x86, x86_64 → ~4 copie) mentre su iOS MapKit è di sistema; inoltre
  è una build **debug** non minificata (niente R8/shrinking) e universale (nessuno
  split per ABI/densità). Per ridurlo in futuro: build `release` con R8 +
  resource shrinking e/o `.aab`/ABI split (solo `arm64-v8a`). Per un APK debug da
  installare a mano va bene così.

### Riusabile dall'app iOS (non riscrivere la logica da zero)
- `InMoto/Resources/routes.json` — i 196 itinerari: copiabile tale e quale negli
  asset Android.
- **Formato roadbook** e logica del parser (`RoadbookParser.swift`): le regole
  (sezioni `TAPPA/PAUSA/ARRIVO`, orari, km/durata, note tra parentesi, link Google
  Maps) si riportano 1:1 in Kotlin.
- Modelli `MotoRoute`, `TripPlan`/`TripPlanItem`, `GeocodedWaypoint` → data class Kotlin.
- Logica `RouteStore` (persistenza offline JSON, personalRoutes/tripPlans/preferiti,
  rinomina) → repository Kotlin con file/DataStore.
- Struttura UI di riferimento: 2 tab (**Bikers Liguria Roadtrip** = viaggi/roadbook
  personali; **Altro** = Viaggi Personali/Preferiti/Guida/Impostazioni).

### Punti difficili / attenzioni
- **Mappe + routing**: l'equivalente di `MKDirections`/`MapKit`. Con OSM → MapLibre
  per il rendering + OSRM per le tratte; con Google → Maps SDK + Directions API (key).
- **Navigazione live** (fase 2): replicare `NavigationSession` (map-matching su
  geometria, progressione in metri, avanzamento tappe, TTS in italiano, camera
  course-up). È un sotto-progetto a sé.
- **GPS**: `FusedLocationProviderClient` (equivalente di `LocationManager`/
  `CoreLocation`), incluso il fix one-shot e i permessi background per la navigazione.
- **Geocoding/autocomplete indirizzi**: equivalente di `CLGeocoder`/
  `AddressCompleter` (Android `Geocoder` o servizio esterno).
- Decidere se Android va in **questo stesso repo** (es. cartella `android/`) o in un
  repo separato; e impostare il relativo workflow CI.
