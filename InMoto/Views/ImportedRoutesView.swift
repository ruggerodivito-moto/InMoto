import SwiftUI

// ── Schermata principale "Tragitti importati" ────────────────────────────────
struct ImportedRoutesView: View {
    @EnvironmentObject var store:    RouteStore
    @EnvironmentObject var appState: AppState
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if store.personalRoutes.isEmpty {
                    emptyState
                } else {
                    routeList
                }
            }
            .navigationTitle("Tragitti personali")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportRouteView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bookmark.slash")
                .font(.system(size: 60))
                .foregroundStyle(.indigo.opacity(0.4))
            Text("Nessun tragitto personale")
                .font(.title2.weight(.semibold))
            Text("Importa i tuoi tragitti da Google Maps\no crea un percorso da A a B.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button { showImport = true } label: {
                Label("Importa tragitto", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            Spacer()
        }
        .padding()
    }

    private var routeList: some View {
        List {
            ForEach(store.personalRoutes) { route in
                NavigationLink(destination: RouteDetailView(route: route)) {
                    RouteCardView(route: route).padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete { offsets in
                offsets.forEach { store.deletePersonalRoute(store.personalRoutes[$0]) }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
    }
}

// ── Form importazione ────────────────────────────────────────────────────────
struct ImportRouteView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    // Modalità di input
    enum Mode: String, CaseIterable {
        case links  = "Link Google Maps"
        case aToB   = "Da A a B"
    }

    @State private var mode: Mode = .links

    // Campi comuni
    @State private var routeName = ""

    // Modalità link
    @State private var rawInput  = ""

    // Modalità A→B
    @State private var startText = ""
    @State private var endText   = ""

    // GPS / Preferiti
    @State private var isGeolocatingStart = false
    @State private var showFavStart = false
    @State private var showFavEnd   = false

    @StateObject private var startCompleter = AddressCompleter()
    @StateObject private var endCompleter   = AddressCompleter()

    // Risultato
    @State private var parsedWaypoints: [ParsedWaypoint] = []
    @State private var preview: MotoRoute?  = nil
    @State private var warnings: [String]   = []
    @State private var errorMsg: String?    = nil
    @State private var isBuilding = false
    @State private var isComputingDistances = false

    private var canVerify: Bool {
        !routeName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (mode == .links
            ? !rawInput.trimmingCharacters(in: .whitespaces).isEmpty
            : !startText.trimmingCharacters(in: .whitespaces).isEmpty &&
              !endText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Nome ──────────────────────────────────────────────────────
                Section {
                    TextField("Es. Giro delle Langhe", text: $routeName)
                        .autocorrectionDisabled()
                } header: { Text("Nome del tragitto") }

                // ── Selettore modalità ────────────────────────────────────────
                Section {
                    Picker("Modalità", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in resetResult() }
                }

                // ── Input in base alla modalità ───────────────────────────────
                if mode == .links {
                    linkInputSection
                } else {
                    aToBInputSection
                }

                // ── Bottone verifica ──────────────────────────────────────────
                Section {
                    Button(action: verifica) {
                        HStack {
                            Spacer()
                            if isBuilding { ProgressView().padding(.trailing, 8) }
                            else { Image(systemName: "arrow.triangle.2.circlepath") }
                            Text(isBuilding ? "Ricostruzione…" : "Costruisci tragitto")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canVerify || isBuilding)
                    .tint(.indigo)

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.subheadline)
                    }
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "info.circle")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                    if isComputingDistances {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Calcolo distanze reali…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Anteprima ─────────────────────────────────────────────────
                if !parsedWaypoints.isEmpty {
                    waypointPreviewSection
                }
                if let prev = preview {
                    routePreviewSection(prev)
                }
            }
            .navigationTitle("Importa tragitto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .sheet(isPresented: $showFavStart) {
                FavoritesPickerSheet { place in
                    startText = place.address
                    startCompleter.clear()
                    resetResult()
                }
            }
            .sheet(isPresented: $showFavEnd) {
                FavoritesPickerSheet { place in
                    endText = place.address
                    endCompleter.clear()
                    resetResult()
                }
            }
        }
    }

    // ── Sezione link ─────────────────────────────────────────────────────────
    private var linkInputSection: some View {
        Section {
            TextEditor(text: $rawInput)
                .frame(minHeight: 140)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .onChange(of: rawInput) { _ in resetResult() }
        } header: {
            Text("Incolla link o luoghi")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accetta (uno per riga):")
                    .foregroundStyle(.secondary)
                Group {
                    Text("• Link Google Maps di un luogo")
                    Text("• Link Google Maps di un percorso completo")
                    Text("• Nomi di luoghi in italiano")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text("Come ottenere il link: apri Google Maps → seleziona il luogo o il percorso → Condividi → Copia link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // ── Sezione A→B ──────────────────────────────────────────────────────────
    private var aToBInputSection: some View {
        Group {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle").foregroundStyle(.green)
                    TextField("Dove parti?", text: $startText)
                        .autocorrectionDisabled()
                        .onChange(of: startText) { _ in
                            startCompleter.update(query: startText)
                            resetResult()
                        }
                    if isGeolocatingStart {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        if !startText.isEmpty {
                            Button { startText = ""; startCompleter.clear() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        Button(action: usaPosizioneAttualeStart) {
                            Image(systemName: "location.fill").foregroundStyle(.blue)
                        }.buttonStyle(.plain)
                        if !store.favoritePlaces.isEmpty {
                            Button { showFavStart = true } label: {
                                Image(systemName: "star.fill").foregroundStyle(.orange)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                ForEach(startCompleter.results) { s in
                    Button {
                        startText = s.fullText
                        startCompleter.clear()
                        hideKeyboard()
                    } label: { addressSuggestionRow(s, color: .green) }
                    .buttonStyle(.plain)
                }
            } header: { Text("Partenza") }
              footer: { Text("Puoi scrivere qualsiasi luogo o indirizzo") }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                    TextField("Dove vuoi arrivare?", text: $endText)
                        .autocorrectionDisabled()
                        .onChange(of: endText) { _ in
                            endCompleter.update(query: endText)
                            resetResult()
                        }
                    if !endText.isEmpty {
                        Button { endText = ""; endCompleter.clear() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    if !store.favoritePlaces.isEmpty {
                        Button { showFavEnd = true } label: {
                            Image(systemName: "star.fill").foregroundStyle(.orange)
                        }.buttonStyle(.plain)
                    }
                }
                ForEach(endCompleter.results) { s in
                    Button {
                        endText = s.fullText
                        endCompleter.clear()
                        hideKeyboard()
                    } label: { addressSuggestionRow(s, color: .red) }
                    .buttonStyle(.plain)
                }
            } header: { Text("Destinazione") }
        }
    }

    private func addressSuggestionRow(_ s: AddressCompleter.Suggestion, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin").foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.subheadline).foregroundStyle(.primary)
                if !s.subtitle.isEmpty {
                    Text(s.subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── Preview tappe parsed ──────────────────────────────────────────────────
    private var waypointPreviewSection: some View {
        Section {
            ForEach(Array(parsedWaypoints.enumerated()), id: \.offset) { i, wp in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(i == 0 ? Color.green
                                  : i == parsedWaypoints.count - 1 ? Color.red
                                  : Color.indigo)
                            .frame(width: 26, height: 26)
                        Text("\(i+1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wp.displayName)
                            .font(.subheadline)
                        if let src = wp.source {
                            Text(src).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label("\(parsedWaypoints.count) tappe estratte", systemImage: "list.number")
        }
    }

    // ── Preview route ─────────────────────────────────────────────────────────
    private func routePreviewSection(_ route: MotoRoute) -> some View {
        Section {
            RouteCardView(route: route)
                .padding(.horizontal, -16).padding(.vertical, 4)

            Text(route.descrizione)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: salva) {
                HStack {
                    Spacer()
                    if isComputingDistances { ProgressView().padding(.trailing, 6) }
                    else { Image(systemName: "bookmark.fill") }
                    Text(isComputingDistances ? "Calcolo distanze…" : "Salva nel tuo elenco")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isComputingDistances)
        } header: {
            Label("Tragitto ricostruito", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    // ── Logica ───────────────────────────────────────────────────────────────
    private func verifica() {
        hideKeyboard()
        errorMsg = nil
        warnings = []
        resetResult()
        isBuilding = true

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            var wps: [ParsedWaypoint] = []
            var warns: [String] = []

            if mode == .links {
                // Parsing linea per linea
                let lines = rawInput
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                for line in lines {
                    if line.lowercased().hasPrefix("http") {
                        let urlToParse: String
                        if GoogleMapsParser.isShortURL(line) {
                            urlToParse = await GoogleMapsParser.resolveShortURL(line) ?? line
                        } else {
                            urlToParse = line
                        }
                        let (parsed, warn) = GoogleMapsParser.parse(urlToParse)
                        if parsed.isEmpty {
                            warns.append(warn ?? "Link non riconosciuto: \(line.prefix(60))…")
                        } else {
                            wps.append(contentsOf: parsed)
                        }
                    } else {
                        wps.append(ParsedWaypoint(displayName: line, gmapsWaypoint: "\(line), Italy", source: nil))
                    }
                }

                guard wps.count >= 2 else {
                    await MainActor.run {
                        errorMsg = wps.isEmpty
                            ? "Nessun luogo riconosciuto. Controlla i link o scrivi i nomi dei luoghi."
                            : "Inserisci almeno 2 tappe per creare un percorso."
                        warnings = warns
                        isBuilding = false
                    }
                    return
                }

                let name  = routeName.trimmingCharacters(in: .whitespaces)
                let tappe = wps.map { $0.displayName }
                let gWps  = wps.map { $0.gmapsWaypoint }

                let baseRoute = MotoRoute(
                    id: UUID().uuidString,
                    nome: name,
                    partenza: tappe.first!, arrivo: tappe.last!,
                    regione: "",
                    km: 0, durataMin: 0,
                    difficolta: "Media", stelle: 0,
                    descrizione: "Tragitto personale con \(wps.count) tapp\(wps.count == 1 ? "a" : "e").",
                    tappe: tappe,
                    waypointsGmaps: gWps,
                    tags: ["personale"],
                    fonte: "Importato", stagione: "Tutto l'anno", isCustom: true,
                    legKm: nil, legMin: nil
                )

                await MainActor.run {
                    parsedWaypoints = wps
                    warnings        = warns
                    preview         = baseRoute
                    isBuilding      = false
                    isComputingDistances = true
                }

                // Calcola distanze reali via MKDirections
                if let result = await computeDistances(for: gWps) {
                    await MainActor.run {
                        if var curr = preview {
                            preview = MotoRoute(
                                id: curr.id, nome: curr.nome,
                                partenza: curr.partenza, arrivo: curr.arrivo,
                                regione: curr.regione,
                                km: result.km, durataMin: result.durataMin,
                                difficolta: curr.difficolta, stelle: curr.stelle,
                                descrizione: curr.descrizione, tappe: curr.tappe,
                                waypointsGmaps: curr.waypointsGmaps,
                                tags: curr.tags, fonte: curr.fonte,
                                stagione: curr.stagione, isCustom: curr.isCustom,
                                legKm: result.legKm, legMin: result.legMin
                            )
                        }
                        isComputingDistances = false
                    }
                } else {
                    await MainActor.run { isComputingDistances = false }
                }

            } else {
                // Modalità A→B
                let s = startText.trimmingCharacters(in: .whitespaces)
                let e = endText.trimmingCharacters(in: .whitespaces)
                let composed = store.composeLocalRoute(da: s, a: e)

                let gWps = composed.waypointsGmaps.isEmpty
                    ? ["\(s), Italy", "\(e), Italy"]
                    : composed.waypointsGmaps

                let baseRoute = MotoRoute(
                    id: UUID().uuidString,
                    nome: routeName.trimmingCharacters(in: .whitespaces),
                    partenza: s, arrivo: e,
                    regione: composed.regione,
                    km: composed.km, durataMin: composed.durataMin,
                    difficolta: composed.difficolta, stelle: composed.stelle,
                    descrizione: composed.descrizione, tappe: composed.tappe,
                    waypointsGmaps: composed.waypointsGmaps,
                    tags: Array(Set(composed.tags + ["personale"])).sorted(),
                    fonte: "Importato", stagione: composed.stagione, isCustom: true,
                    legKm: composed.legKm, legMin: composed.legMin
                )

                await MainActor.run {
                    parsedWaypoints = gWps.enumerated().map { i, wp in
                        ParsedWaypoint(displayName: composed.tappe[safe: i] ?? wp, gmapsWaypoint: wp, source: "DB")
                    }
                    preview = baseRoute
                    isBuilding = false
                    // Calcola distanze reali se il DB non le ha
                    if composed.km == 0 { isComputingDistances = true }
                }

                if composed.km == 0 {
                    if let result = await computeDistances(for: gWps) {
                        await MainActor.run {
                            if var curr = preview {
                                preview = MotoRoute(
                                    id: curr.id, nome: curr.nome,
                                    partenza: curr.partenza, arrivo: curr.arrivo,
                                    regione: curr.regione,
                                    km: result.km, durataMin: result.durataMin,
                                    difficolta: curr.difficolta, stelle: curr.stelle,
                                    descrizione: curr.descrizione, tappe: curr.tappe,
                                    waypointsGmaps: curr.waypointsGmaps,
                                    tags: curr.tags, fonte: curr.fonte,
                                    stagione: curr.stagione, isCustom: curr.isCustom,
                                    legKm: result.legKm, legMin: result.legMin
                                )
                            }
                            isComputingDistances = false
                        }
                    } else {
                        await MainActor.run { isComputingDistances = false }
                    }
                }
            }
        }
    }

    /// Calcola km e durata reali tra i waypoint usando MKDirections
    private func computeDistances(for waypoints: [String]) async
        -> (km: Int, durataMin: Int, legKm: [Int], legMin: [Int])? {
        guard let geoWps = try? await RouterService.shared.geocodeWaypointsMixed(waypoints),
              geoWps.count >= 2,
              let legs = try? await RouterService.shared.computeLegs(for: geoWps) else { return nil }
        let km     = max(1, Int(legs.reduce(0) { $0 + $1.distanceMeters } / 1000))
        let mins   = max(1, Int(legs.reduce(0) { $0 + $1.durationSeconds } / 60))
        let legKms = legs.map { max(1, Int($0.distanceMeters / 1000)) }
        let legMin = legs.map { max(1, Int($0.durationSeconds / 60)) }
        return (km, mins, legKms, legMin)
    }

    private func salva() {
        guard let route = preview else { return }
        store.savePersonalRoute(route)
        dismiss()
    }

    private func resetResult() {
        parsedWaypoints = []
        preview         = nil
        errorMsg        = nil
        isComputingDistances = false
    }

    private func usaPosizioneAttualeStart() {
        isGeolocatingStart = true
        LocationManager.shared.requestPermission()
        LocationManager.shared.start()
        Task {
            var attempts = 0
            while attempts < 20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let loc = LocationManager.shared.location {
                    let addr = await RouterService.reverseGeocode(loc)
                    await MainActor.run {
                        startText = addr.isEmpty ? "Posizione attuale" : addr
                        startCompleter.clear()
                        isGeolocatingStart = false
                        resetResult()
                    }
                    return
                }
                attempts += 1
            }
            await MainActor.run { isGeolocatingStart = false }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// ── Modello waypoint parsed ──────────────────────────────────────────────────
struct ParsedWaypoint {
    let displayName:    String   // testo mostrato all'utente
    let gmapsWaypoint:  String   // stringa usata per Google Maps (coord o nome)
    let source:         String?  // "URL", "DB", nil = testo libero
}

// ── Parser URL Google Maps ───────────────────────────────────────────────────
enum GoogleMapsParser {

    // Riconosce URL abbreviati che richiedono risoluzione HTTP
    static func isShortURL(_ urlString: String) -> Bool {
        let s = urlString.lowercased()
        return s.contains("goo.gl") || s.contains("maps.app") || s.contains("g.co/maps")
    }

    // Segue il redirect e restituisce l'URL finale (es. google.com/maps/place/…)
    static func resolveShortURL(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            // URLSession segue i redirect automaticamente; response.url è l'URL finale
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url?.absoluteString
        } catch {
            return nil
        }
    }

    /// Restituisce (waypoints estratti, eventuale messaggio di warning)
    static func parse(_ urlString: String) -> ([ParsedWaypoint], String?) {
        guard let url = URL(string: urlString) else {
            return ([], "URL non valido")
        }
        let path = url.path

        // ── Percorso con tappe: /maps/dir/A/B/C/ ────────────────────────────
        if path.contains("/dir/") {
            let stops = extractDirStops(from: path)
            if !stops.isEmpty {
                let wps = stops.map {
                    ParsedWaypoint(displayName: $0, gmapsWaypoint: "\($0), Italy", source: "Google Maps percorso")
                }
                return (wps, nil)
            }
        }

        // ── Luogo singolo: /maps/place/Name/@lat,lon ─────────────────────────
        if path.contains("/place/") {
            // Preferisci coordinate (più precise)
            if let coord = extractCoordinates(from: urlString) {
                let name = extractPlaceName(from: path) ?? coord
                return ([ParsedWaypoint(displayName: name,
                                        gmapsWaypoint: coord,
                                        source: "Google Maps luogo")], nil)
            }
            if let name = extractPlaceName(from: path) {
                return ([ParsedWaypoint(displayName: name,
                                        gmapsWaypoint: "\(name), Italy",
                                        source: "Google Maps luogo")], nil)
            }
        }

        // ── Ricerca generica con coordinate ──────────────────────────────────
        if let coord = extractCoordinates(from: urlString) {
            return ([ParsedWaypoint(displayName: coord,
                                    gmapsWaypoint: coord,
                                    source: "Coordinate")], nil)
        }

        return ([], nil)
    }

    // Estrae tappe da /dir/Partenza/Tappa1/Tappa2/Arrivo/
    private static func extractDirStops(from path: String) -> [String] {
        guard let range = path.range(of: "/dir/") else { return [] }
        let after = String(path[range.upperBound...])
        return after
            .components(separatedBy: "/")
            .compactMap { seg -> String? in
                let decoded = seg.removingPercentEncoding?
                    .replacingOccurrences(of: "+", with: " ")
                    ?? seg
                let clean = decoded.trimmingCharacters(in: .whitespaces)
                // Salta segmenti vuoti o che sembrano parametri interni
                guard !clean.isEmpty,
                      !clean.hasPrefix("@"),
                      !clean.hasPrefix("data="),
                      !clean.contains("=") else { return nil }
                return clean
            }
    }

    // Estrae nome luogo da /place/Nome+Luogo/
    private static func extractPlaceName(from path: String) -> String? {
        guard let range = path.range(of: "/place/") else { return nil }
        let after = String(path[range.upperBound...])
        return after
            .components(separatedBy: "/").first?
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .nilIfEmpty
    }

    // Estrae @lat,lon dall'URL
    private static func extractCoordinates(from urlString: String) -> String? {
        guard let atRange = urlString.range(of: "@") else { return nil }
        let after = String(urlString[atRange.upperBound...])
        let parts  = after.components(separatedBy: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        // Filtra coordinate valide
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return "\(lat),\(lon)"
    }
}

// ── Estensioni helper ────────────────────────────────────────────────────────
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
