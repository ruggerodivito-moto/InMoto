import SwiftUI

struct RouteDetailView: View {
    let route: MotoRoute
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var waypoints: [String]
    @State private var newWaypoint = ""
    @State private var showAddField = false
    @State private var showNavigator = false

    init(route: MotoRoute) {
        self.route = route
        _waypoints = State(initialValue: route.waypointsGmaps)
    }

    var isCustom: Bool { route.isCustom == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                descSection
                Divider()
                waypointsSection
                Divider()
                infoSection
                mapsSection
            }
        }
        .navigationTitle(route.nome)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                    appState.selectedTab = 0
                } label: {
                    Image(systemName: "house.fill")
                }
            }
        }
        .fullScreenCover(isPresented: $showNavigator) {
            DownloadPreparationView(route: route)
        }
    }

    // ── Header ───────────────────────────────────────────────────────────────
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCustom {
                Label("Percorso su misura generato", systemImage: "wand.and.sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.orange.gradient)
                    .clipShape(Capsule())
            }

            HStack(alignment: .top) {
                Text(route.nome)
                    .font(.title2.weight(.semibold))
                Spacer()
                DiffBadge(level: route.difficolta)
            }

            StarRow(value: route.stelle)

            Label("\(route.partenza)  →  \(route.arrivo)", systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.indigo)
                .fontWeight(.medium)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCustom ? "~\(route.km) km" : "\(route.km) km")
                        .font(.headline)
                    Text("distanza\(isCustom ? " stimata" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCustom ? "~\(route.durataFormattata)" : route.durataFormattata)
                        .font(.headline)
                    Text("durata\(isCustom ? " stimata" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.regione)
                        .font(.headline)
                        .lineLimit(1)
                    Text("regione")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    // ── Descrizione ──────────────────────────────────────────────────────────
    private var descSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.descrizione)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(16)
    }

    // ── Tappe / Waypoints ────────────────────────────────────────────────────
    private var waypointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tappe del percorso", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation { showAddField.toggle() } }) {
                    Image(systemName: showAddField ? "minus.circle" : "plus.circle")
                        .foregroundStyle(.indigo)
                }
            }

            ForEach(Array(waypoints.enumerated()), id: \.offset) { i, wp in
                HStack(spacing: 12) {
                    // Numero/icona
                    ZStack {
                        Circle()
                            .fill(i < route.waypointsGmaps.count ? Color.indigo : Color.orange)
                            .frame(width: 28, height: 28)
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Text(wp.components(separatedBy: ",").first ?? wp)
                        .font(.subheadline)
                    Spacer()
                    // Rimuovi solo le tappe aggiunte
                    if i >= route.waypointsGmaps.count {
                        Button(action: { waypoints.remove(at: i) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
                .padding(.vertical, 4)
                if i < waypoints.count - 1 {
                    if let legKm = route.legKm, let legMin = route.legMin, i < legKm.count {
                        VStack(spacing: 0) {
                            HStack {
                                Spacer().frame(width: 28)
                                Rectangle().fill(Color(.systemGray5)).frame(width: 1, height: 5)
                                Spacer()
                            }
                            HStack {
                                Spacer().frame(width: 40)
                                Label("\(legKm[i]) km · \(legMin[i]) min", systemImage: "road.lanes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            HStack {
                                Spacer().frame(width: 28)
                                Rectangle().fill(Color(.systemGray5)).frame(width: 1, height: 5)
                                Spacer()
                            }
                        }
                    } else {
                        HStack {
                            Spacer().frame(width: 14)
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: 1, height: 14)
                                .padding(.leading, 14)
                            Spacer()
                        }
                    }
                }
            }

            if showAddField {
                HStack {
                    TextField("Aggiungi tappa (es. Passo Faiallo, Italy)", text: $newWaypoint)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Button("Aggiungi") {
                        let trimmed = newWaypoint.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            waypoints.append(trimmed)
                            newWaypoint = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(newWaypoint.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Inserisci il luogo in italiano o inglese per Google Maps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // ── Info ─────────────────────────────────────────────────────────────────
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Informazioni", systemImage: "info.circle")
                .font(.headline)
            HStack(spacing: 10) {
                if !route.stagione.isEmpty {
                    infoChip(icon: "calendar", text: route.stagione)
                }
                if !route.fonte.isEmpty {
                    infoChip(icon: "star.circle", text: route.fonte)
                }
            }
            if !route.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(route.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }
            }
            if isCustom && !route.fonte.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Composto da:").font(.caption.weight(.semibold))
                        Text(route.fonte).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
    }

    private func infoChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .lineLimit(1)
    }

    // ── Maps CTA ─────────────────────────────────────────────────────────────
    private var mapsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Navigazione", systemImage: "map.fill")
                .font(.headline)

            Button(action: { showNavigator = true }) {
                Label("Naviga con InMoto", systemImage: "location.north.fill")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(waypoints.isEmpty)

            Text("Percorso offline con avanzamento automatico tra le tappe.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Button(action: openGoogleMaps) {
                Label("Apri in Google Maps", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)

            Text("Evita automaticamente autostrade e pedaggi. Include tutte le tappe elencate sopra.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.5))
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    private func openGoogleMaps() {
        guard !waypoints.isEmpty else { return }
        let encode: (String) -> String = {
            $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0
        }

        // App Google Maps: supporta avoid=tolls,highways
        if let gmScheme = URL(string: "comgooglemaps://"),
           UIApplication.shared.canOpenURL(gmScheme) {
            let origin = encode(waypoints.first!)
            let dests  = waypoints.dropFirst().map { encode($0) }.joined(separator: "+to:")
            let str = "comgooglemaps://?saddr=\(origin)&daddr=\(dests)&directionsmode=driving&avoid=tolls,highways"
            if let url = URL(string: str) { UIApplication.shared.open(url); return }
        }

        // Fallback web: no avoid su multi-stop, ma funziona senza app
        let parts = waypoints.map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0
        }
        let urlStr = "https://www.google.com/maps/dir/" + parts.joined(separator: "/") + "/"
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
    }

}

// ── FlowLayout ───────────────────────────────────────────────────────────────
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
