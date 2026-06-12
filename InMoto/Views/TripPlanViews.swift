import SwiftUI
import MapKit
import CoreLocation

// ═════════════════════════════════════════════════════════════════════════════
// Dettaglio viaggio: timeline tappe/pause. Ogni riga è navigabile —
//   · tappa  → dettaglio percorso su mappa + avvio navigazione
//   · pausa/arrivo → posizione del luogo su mappa
// ═════════════════════════════════════════════════════════════════════════════

struct TripPlanDetailView: View {
    let plan: TripPlan

    var body: some View {
        List {
            // ── Intestazione ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if !plan.sottotitolo.isEmpty {
                        Text(plan.sottotitolo)
                            .font(.headline)
                    }
                    HStack(spacing: 14) {
                        if plan.totaleKm > 0 {
                            Label("\(plan.totaleKm) km", systemImage: "road.lanes")
                        }
                        if plan.totaleMin > 0 {
                            Label(plan.durataFormattata, systemImage: "clock")
                        }
                        Label("\(plan.tappe.count) tappe", systemImage: "flag.checkered")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // ── Timeline ─────────────────────────────────────────────────────
            Section {
                ForEach(plan.items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        TripItemRow(item: item)
                    }
                }
            } header: {
                Text("Programma")
            } footer: {
                Text("Tocca una tappa per vederne il percorso e avviare la navigazione. Tocca una pausa per vederne la posizione.")
            }

            // ── Nota finale ───────────────────────────────────────────────────
            if !plan.notaFinale.isEmpty {
                Section {
                    Text(plan.notaFinale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Per il ritorno")
                }
            }
        }
        .navigationTitle(plan.nome)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destination(for item: TripPlanItem) -> some View {
        switch item.kind {
        case .tappa:
            TripStageDetailView(plan: plan, item: item)
        case .pausa, .arrivo:
            TripPlaceView(item: item)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Riga della timeline (tappa / pausa / arrivo) — solo presentazione
// ═════════════════════════════════════════════════════════════════════════════

struct TripItemRow: View {
    let item: TripPlanItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.titolo)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(badgeColor)
                    Spacer()
                    if !item.orarioFormattato.isEmpty {
                        Text(item.orarioFormattato)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.nome)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if item.kind == .tappa, item.km > 0 || item.durataMin > 0 {
                    HStack(spacing: 10) {
                        if item.km > 0 {
                            Label("\(item.km) km", systemImage: "road.lanes")
                        }
                        if item.durataMin > 0 {
                            let h = item.durataMin / 60, m = item.durataMin % 60
                            Label(h > 0 ? "\(h)h\(m > 0 ? " \(m)'" : "")" : "\(m)'",
                                  systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if item.kind == .tappa, item.tappeNomi.count > 2 {
                    Text("\(item.tappeNomi.count) punti di passaggio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !item.nota.isEmpty {
                    Label(item.nota, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var badgeColor: Color {
        switch item.kind {
        case .tappa:  return .orange
        case .pausa:  return .teal
        case .arrivo: return .green
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor.opacity(0.15))
                .frame(width: 34, height: 34)
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(badgeColor)
        }
    }

    private var iconName: String {
        switch item.kind {
        case .tappa:  return "point.topleft.down.curvedto.point.bottomright.up"
        case .pausa:  return "cup.and.saucer.fill"
        case .arrivo: return "flag.checkered"
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dettaglio di una tappa: percorso su mappa + punti di passaggio + avvio
// ═════════════════════════════════════════════════════════════════════════════

struct TripStageDetailView: View {
    let plan: TripPlan
    let item: TripPlanItem

    @StateObject private var vm = DownloadPreparationViewModel()
    @ObservedObject private var locationMgr = LocationManager.shared
    @State private var navigating: PreparedNav?
    @State private var startPrompt: StartFromHerePrompt?
    @State private var addingCurrentPosition = false

    private var motoRoute: MotoRoute { plan.motoRoute(for: item) }
    private var navigable: Bool { item.waypointsGmaps.count >= 2 }

    /// Oltre questa distanza dal primo punto della tappa si chiede se aggiungere
    /// la posizione attuale come partenza (sotto, si è "già sul posto")
    private let startProximityThreshold: Double = 300

    var body: some View {
        List {
            // ── Mappa anteprima percorso ──────────────────────────────────────
            Section {
                StageMapPreview(navRoute: vm.navigationRoute, status: previewStatus)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }

            // ── Riepilogo ─────────────────────────────────────────────────────
            Section {
                if !item.orarioFormattato.isEmpty {
                    Label(item.orarioFormattato, systemImage: "clock")
                }
                HStack(spacing: 18) {
                    if let nav = vm.navigationRoute {
                        Label(nav.formattedDistance, systemImage: "road.lanes")
                        Label(nav.formattedDuration, systemImage: "timer")
                    } else {
                        if item.km > 0 { Label("\(item.km) km", systemImage: "road.lanes") }
                        if item.durataMin > 0 {
                            let h = item.durataMin / 60, m = item.durataMin % 60
                            Label(h > 0 ? "\(h)h \(m)min" : "\(m)min", systemImage: "timer")
                        }
                    }
                }
                .font(.subheadline)
                if !item.nota.isEmpty {
                    Label(item.nota, systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            // ── Punti di passaggio ────────────────────────────────────────────
            if item.tappeNomi.count >= 2 {
                Section {
                    ForEach(Array(item.tappeNomi.enumerated()), id: \.offset) { i, name in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(i == 0 ? Color.green
                                          : i == item.tappeNomi.count - 1 ? Color.red
                                          : Color.orange)
                                    .frame(width: 26, height: 26)
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Text(name.components(separatedBy: ",").first ?? name)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Punti di passaggio")
                }
            }

            // ── Avvio navigazione ─────────────────────────────────────────────
            Section {
                if let err = vm.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Button {
                        Task { await vm.prepare(route: motoRoute) }
                    } label: {
                        Label("Riprova", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else if let nav = vm.navigationRoute {
                    Button {
                        onStartTapped(nav)
                    } label: {
                        HStack {
                            if addingCurrentPosition {
                                ProgressView().tint(.white)
                                Text("Calcolo collegamento…")
                            } else {
                                Label("Inizia navigazione", systemImage: "location.north.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(addingCurrentPosition)

                    Text("Avanzamento automatico tra i punti: superato un punto, la navigazione passa da sola al successivo, senza toccare il telefono.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if navigable {
                    HStack {
                        ProgressView()
                        Text("Preparazione percorso…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Tappa senza percorso riconosciuto (link mancante o non leggibile).",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(item.titolo)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if navigable, vm.navigationRoute == nil, vm.error == nil {
                await vm.prepare(route: motoRoute)
            }
        }
        .onAppear {
            // Un fix di posizione pronto per capire se sei già al punto di partenza
            locationMgr.requestPermission()
            locationMgr.requestOneShot()
        }
        .confirmationDialog("Non sei al punto di partenza della tappa",
                            isPresented: Binding(get: { startPrompt != nil },
                                                 set: { if !$0 { startPrompt = nil } }),
                            titleVisibility: .visible,
                            presenting: startPrompt) { prompt in
            Button("Aggiungi la mia posizione attuale") {
                startWithCurrentPosition(prompt.nav, from: prompt.here)
            }
            Button("Parti dalla prima tappa") {
                navigating = PreparedNav(navRoute: prompt.nav, motoRoute: motoRoute)
            }
            Button("Annulla", role: .cancel) {}
        } message: { prompt in
            Text("Sei a circa \(formatDistance(prompt.distance)) dall'inizio della tappa. Vuoi aggiungere la tua posizione attuale come punto di partenza, prima del primo punto della tappa?")
        }
        .fullScreenCover(item: $navigating) { prepared in
            NavigationStack {
                NavigatorView(navRoute: prepared.navRoute, motoRoute: prepared.motoRoute)
            }
        }
    }

    // MARK: - Avvio navigazione

    /// Tap su "Inizia navigazione": se la posizione attuale è nota ed è lontana
    /// dal primo punto della tappa, chiede se anteporre la posizione attuale.
    private func onStartTapped(_ nav: NavigationRoute) {
        // Aggiorna il fix per la prossima volta
        locationMgr.requestOneShot()
        if let here = locationMgr.location?.coordinate, let first = nav.waypoints.first {
            let distance = CLLocation(latitude: here.latitude, longitude: here.longitude)
                .distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
            if distance > startProximityThreshold {
                startPrompt = StartFromHerePrompt(nav: nav, here: here, distance: distance)
                return
            }
        }
        navigating = PreparedNav(navRoute: nav, motoRoute: motoRoute)
    }

    /// Antepone la posizione attuale come primo waypoint, calcolando la tratta
    /// di collegamento fino al primo punto della tappa, poi avvia la navigazione.
    private func startWithCurrentPosition(_ nav: NavigationRoute,
                                          from here: CLLocationCoordinate2D) {
        guard let first = nav.waypoints.first else {
            navigating = PreparedNav(navRoute: nav, motoRoute: motoRoute)
            return
        }
        addingCurrentPosition = true
        Task {
            defer { addingCurrentPosition = false }
            let current = GeocodedWaypoint(name: "Posizione attuale",
                                           latitude: here.latitude, longitude: here.longitude)
            do {
                let connector = try await RouterService.shared.connectorLeg(from: here, to: first)
                let merged = NavigationRoute(routeId: nav.routeId,
                                             routeName: nav.routeName,
                                             waypoints: [current] + nav.waypoints,
                                             legs: [connector] + nav.legs)
                navigating = PreparedNav(navRoute: merged, motoRoute: motoRoute)
            } catch {
                // Collegamento non calcolabile: parti comunque dalla prima tappa
                navigating = PreparedNav(navRoute: nav, motoRoute: motoRoute)
            }
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 50).rounded()) * 50) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    private var previewStatus: StageMapPreview.Status {
        if vm.navigationRoute != nil { return .ready }
        if vm.error != nil { return .failed }
        return navigable ? .loading : .failed
    }
}

/// Percorso preparato pronto per la navigazione (item per fullScreenCover).
private struct PreparedNav: Identifiable {
    let id = UUID()
    let navRoute: NavigationRoute
    let motoRoute: MotoRoute
}

/// Richiesta di conferma per anteporre la posizione attuale alla partenza.
private struct StartFromHerePrompt: Identifiable {
    let id = UUID()
    let nav: NavigationRoute
    let here: CLLocationCoordinate2D
    let distance: Double
}

// ═════════════════════════════════════════════════════════════════════════════
// Mappa statica del percorso di una tappa (polilinea + pin tappe)
// ═════════════════════════════════════════════════════════════════════════════

struct StageMapPreview: View {
    enum Status { case loading, ready, failed }

    let navRoute: NavigationRoute?
    let status: Status

    var body: some View {
        ZStack {
            if let nav = navRoute {
                let points = nav.legs.flatMap { $0.polylineCoordinates }
                Map(initialPosition: .region(MapMath.region(fitting: points.isEmpty
                                                             ? nav.waypoints.map { $0.coordinate }
                                                             : points))) {
                    if points.count >= 2 {
                        MapPolyline(coordinates: points)
                            .stroke(.blue, lineWidth: 5)
                    }
                    ForEach(Array(nav.waypoints.enumerated()), id: \.offset) { i, wp in
                        Marker("\(i + 1)", coordinate: wp.coordinate)
                            .tint(i == 0 ? .green
                                  : i == nav.waypoints.count - 1 ? .red : .orange)
                    }
                }
            } else {
                Rectangle().fill(Color(.systemGray6))
                VStack(spacing: 8) {
                    switch status {
                    case .loading:
                        ProgressView()
                        Text("Calcolo percorso…")
                    case .failed:
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Anteprima non disponibile")
                    case .ready:
                        EmptyView()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Posizione di una pausa / arrivo: mappa con pin + apertura in Mappe
// ═════════════════════════════════════════════════════════════════════════════

struct TripPlaceView: View {
    let item: TripPlanItem

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLoading = true
    @State private var failed = false

    private var placeName: String {
        item.tappeNomi.first ?? item.nome
    }

    var body: some View {
        List {
            Section {
                ZStack {
                    if let coord = coordinate {
                        Map(initialPosition: .region(
                            MKCoordinateRegion(center: coord,
                                               span: MKCoordinateSpan(latitudeDelta: 0.02,
                                                                      longitudeDelta: 0.02)))) {
                            Marker(placeName.components(separatedBy: ",").first ?? placeName,
                                   coordinate: coord)
                                .tint(item.kind == .arrivo ? .green : .teal)
                        }
                    } else {
                        Rectangle().fill(Color(.systemGray6))
                        VStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                Text("Localizzazione…")
                            } else {
                                Image(systemName: "mappin.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Posizione non trovata")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.nome)
                        .font(.headline)
                    if !item.orarioFormattato.isEmpty {
                        Label(item.orarioFormattato, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.nota.isEmpty {
                    Label(item.nota, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            if coordinate != nil {
                Section {
                    Button(action: openAppleMaps) {
                        Label("Apri in Mappe", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)

                    Button(action: openGoogleMaps) {
                        Label("Apri in Google Maps", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                }
            }
        }
        .navigationTitle(item.titolo)
        .navigationBarTitleDisplayMode(.inline)
        .task { await locate() }
    }

    private func locate() async {
        let input = item.waypointsGmaps.first ?? placeName
        guard let geo = try? await RouterService.shared.geocodeWaypointsMixed([input]),
              let wp = geo.first else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }
        await MainActor.run {
            coordinate = wp.coordinate
            isLoading = false
        }
    }

    private func openAppleMaps() {
        guard let coord = coordinate else { return }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        mapItem.name = placeName.components(separatedBy: ",").first ?? placeName
        mapItem.openInMaps()
    }

    private func openGoogleMaps() {
        guard let coord = coordinate else { return }
        let q = "\(coord.latitude),\(coord.longitude)"
        if let scheme = URL(string: "comgooglemaps://"),
           UIApplication.shared.canOpenURL(scheme),
           let url = URL(string: "comgooglemaps://?q=\(q)&center=\(q)") {
            UIApplication.shared.open(url)
            return
        }
        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Utility geografiche
// ═════════════════════════════════════════════════════════════════════════════

enum MapMath {
    /// Regione che inquadra un insieme di coordinate, con un margine attorno.
    static func region(fitting coords: [CLLocationCoordinate2D],
                       padding: Double = 1.4) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.0, longitude: 8.0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * padding),
            longitudeDelta: max(0.01, (maxLon - minLon) * padding))
        return MKCoordinateRegion(center: center, span: span)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Import roadbook: incolla il testo → anteprima → salva
// ═════════════════════════════════════════════════════════════════════════════

struct RoadbookImportView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var isParsing = false
    @State private var parsedPlan: TripPlan?
    @State private var customName = ""
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .onChange(of: rawText) { _ in
                            parsedPlan = nil
                            errorMsg = nil
                        }
                } header: {
                    Text("Incolla il roadbook")
                } footer: {
                    Text("Formato: NOME, poi sezioni TAPPA n / PAUSA n / ARRIVO. Ogni sezione può contenere link Google Maps, orari (7:30 - 9:45), distanze (148Km) e durate (2h 15'). Le note tra parentesi vengono conservate.")
                }

                Section {
                    Button(action: analizza) {
                        HStack {
                            Spacer()
                            if isParsing {
                                ProgressView().padding(.trailing, 8)
                            } else {
                                Image(systemName: "doc.text.magnifyingglass")
                            }
                            Text(isParsing ? "Lettura link in corso…" : "Analizza roadbook")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                    .tint(.indigo)

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                if let plan = parsedPlan {
                    Section {
                        TextField("Nome del viaggio", text: $customName)
                            .autocorrectionDisabled()
                            .font(.headline)
                    } header: {
                        Text("Nome del viaggio")
                    } footer: {
                        Text("Puoi modificare il nome proposto prima di salvare.")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(customName.isEmpty ? plan.nome : customName).font(.headline)
                            if !plan.sottotitolo.isEmpty {
                                Text(plan.sottotitolo).font(.subheadline).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                if plan.totaleKm > 0 { Text("\(plan.totaleKm) km") }
                                if plan.totaleMin > 0 { Text(plan.durataFormattata) }
                                Text("\(plan.tappe.count) tappe")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        ForEach(plan.items) { item in
                            TripItemRow(item: item)
                        }

                        Button {
                            var toSave = plan
                            let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { toSave.nome = trimmed }
                            store.saveTripPlan(toSave)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "bookmark.fill")
                                Text("Salva viaggio").fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } header: {
                        Label("Viaggio riconosciuto", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Importa roadbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func analizza() {
        isParsing = true
        errorMsg = nil
        Task {
            let plan = await RoadbookParser.parse(rawText)
            await MainActor.run {
                isParsing = false
                if let plan {
                    parsedPlan = plan
                    if customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        customName = plan.nome
                    }
                    let broken = plan.tappe.filter { $0.waypointsGmaps.count < 2 }
                    if !broken.isEmpty {
                        errorMsg = "Attenzione: \(broken.map { $0.titolo }.joined(separator: ", ")) senza percorso riconosciuto (link mancante o non leggibile)."
                    }
                } else {
                    errorMsg = "Nessuna sezione TAPPA trovata nel testo. Controlla il formato."
                }
            }
        }
    }
}
