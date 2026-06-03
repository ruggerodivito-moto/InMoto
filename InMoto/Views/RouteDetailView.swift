import SwiftUI
import MapKit

struct RouteDetailView: View {
    let route: MotoRoute
    @State private var waypoints: [String]
    @State private var newWaypoint = ""
    @State private var showAddField = false

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
            Label("Apri su Maps", systemImage: "map.fill")
                .font(.headline)

            HStack(spacing: 12) {
                // Apple Maps
                Button(action: openAppleMaps) {
                    Label("Apple Maps", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                // Google Maps
                Button(action: openGoogleMaps) {
                    Label("Google Maps", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
            Text("Include tutte le tappe elencate sopra, comprese quelle aggiunte.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.5))
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    private func openGoogleMaps() {
        let parts = waypoints.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
        let urlStr = "https://www.google.com/maps/dir/" + parts.joined(separator: "/") + "/"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private func openAppleMaps() {
        guard !waypoints.isEmpty else { return }
        let geocoder = CLGeocoder()
        var mapItems: [MKMapItem] = []
        let group = DispatchGroup()

        for wp in waypoints {
            group.enter()
            geocoder.geocodeAddressString(wp) { placemarks, _ in
                if let pm = placemarks?.first {
                    mapItems.append(MKMapItem(placemark: MKPlacemark(placemark: pm)))
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard mapItems.count >= 2 else { return }
            let options: [String: Any] = [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
            MKMapItem.openMaps(with: mapItems, launchOptions: options)
        }
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
