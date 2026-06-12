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

## 🟡 PROGETTO APERTO — Versione Android (da riprendere)

L'utente ha chiesto di creare **una versione Android dell'app**. Lavoro **non
ancora iniziato**: prima di generare codice servono 4 decisioni (l'utente ha
interrotto le domande chiedendo di annotare tutto qui). Quando si riprende,
 riproporre queste scelte (con le raccomandazioni) e poi partire.

### Decisioni da prendere (con raccomandazione)
1. **Tecnologia** → *consiglio: Kotlin + Jetpack Compose* (nativa, rispecchia
   SwiftUI, l'app iOS resta invariata). Alternative: Flutter (codice unico ma
   riscrittura futura di iOS), Kotlin Multiplatform (condivide logica, UI separate).
2. **Scope v1** → *consiglio: base prima, navigazione dopo* — v1 = sfoglia
   itinerari offline + import roadbook/viaggi + mappe statiche + apertura in Google
   Maps; fase 2 = navigatore live (map-matching, avanzamento automatico, voce,
   course-up). La parità completa subito è molto più lunga.
3. **Provider mappe** → *consiglio per partire: MapLibre/OSM (nessuna API key né
   costi; routing via OSRM pubblico)*. Alternativa: Google Maps SDK (resa migliore
   ma richiede API key Google Cloud, possibili costi oltre soglia gratuita).
4. **Build/installazione** → *consiglio: GitHub Actions → APK debug* (come iOS ma
   più semplice: l'APK si installa diretto, niente firma per sideload; serve un
   device Android per provarlo). Alternative: Android Studio locale; oppure solo
   progetto+codice se non c'è ancora un device. **Verificare se l'utente ha un
   telefono Android / emulatore.**

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
