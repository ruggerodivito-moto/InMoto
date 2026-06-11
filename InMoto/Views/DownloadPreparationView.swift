import SwiftUI
import CoreLocation

// MARK: - ViewModel

@MainActor
class DownloadPreparationViewModel: ObservableObject {
    @Published var geocodingStatus: StepStatus = .waiting
    @Published var routingStatus: StepStatus = .waiting
    @Published var cachingStatus: StepStatus = .waiting
    @Published var error: String?
    @Published var navigationRoute: NavigationRoute?

    var isWorking: Bool {
        geocodingStatus == .inProgress || routingStatus == .inProgress || cachingStatus == .inProgress
    }

    func prepare(route: MotoRoute) async {
        error = nil
        navigationRoute = nil
        geocodingStatus = .waiting
        routingStatus = .waiting
        cachingStatus = .waiting

        // Usa la cache se disponibile
        if let cached = RouterService.shared.cachedRoute(for: route.id) {
            geocodingStatus = .done
            routingStatus = .done
            cachingStatus = .done
            navigationRoute = cached
            return
        }

        guard !route.waypointsGmaps.isEmpty else {
            error = "Questo percorso non ha tappe definite"
            return
        }

        // Step 1 — Geocoding (gestisce anche coordinate "lat,lon" dai link importati)
        geocodingStatus = .inProgress
        let waypoints: [GeocodedWaypoint]
        do {
            let raw = try await RouterService.shared.geocodeWaypointsMixed(route.waypointsGmaps)
            // Nei viaggi composti i tragitti condividono nodi: comprimi i
            // waypoint consecutivi che ricadono nello stesso punto
            waypoints = Self.mergeCloseWaypoints(raw)
            geocodingStatus = .done
        } catch {
            geocodingStatus = .failed
            self.error = error.localizedDescription
            return
        }

        guard waypoints.count >= 2 else {
            geocodingStatus = .failed
            self.error = "Servono almeno due tappe distinte"
            return
        }

        // Step 2 — Calcolo percorso
        routingStatus = .inProgress
        let legs: [RouteLeg]
        do {
            legs = try await RouterService.shared.computeLegs(for: waypoints)
            routingStatus = .done
        } catch {
            routingStatus = .failed
            self.error = error.localizedDescription
            return
        }

        // Step 3 — Salvataggio offline
        cachingStatus = .inProgress
        let navRoute = NavigationRoute(
            routeId: route.id,
            routeName: route.nome,
            waypoints: waypoints,
            legs: legs
        )
        RouterService.shared.cacheRoute(navRoute)
        cachingStatus = .done
        navigationRoute = navRoute
    }

    /// Comprime waypoint consecutivi più vicini di `threshold` metri: succede
    /// quando si concatenano tragitti con nodi in comune, dove lo stesso luogo
    /// (anche con nomi diversi) viene geocodificato due volte
    static func mergeCloseWaypoints(_ wps: [GeocodedWaypoint],
                                    threshold: Double = 250) -> [GeocodedWaypoint] {
        var out: [GeocodedWaypoint] = []
        for wp in wps {
            if let last = out.last,
               CLLocation(latitude: last.latitude, longitude: last.longitude)
                   .distance(from: CLLocation(latitude: wp.latitude, longitude: wp.longitude)) < threshold {
                continue
            }
            out.append(wp)
        }
        return out
    }
}

// MARK: - View

struct DownloadPreparationView: View {
    let route: MotoRoute
    @StateObject private var vm = DownloadPreparationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                headerSection
                Spacer().frame(height: 52)
                stepsSection
                Spacer()
                bottomSection
                Spacer().frame(height: 36)
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(vm.isWorking)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.navigationRoute != nil {
                        Button(action: { RouterService.shared.deleteCachedRoute(for: route.id) }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Ricalcola")
                    }
                }
            }
            .task { await vm.prepare(route: route) }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Preparazione percorso")
                .font(.title2.weight(.semibold))
            Text(route.nome)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            PrepStepRow(
                icon: "location.circle.fill",
                title: "Geolocalizzazione tappe",
                subtitle: "\(route.waypointsGmaps.count) luoghi da localizzare",
                status: vm.geocodingStatus
            )
            PrepStepRow(
                icon: "arrow.triangle.turn.up.right.circle.fill",
                title: "Calcolo percorso",
                subtitle: "\(max(0, route.waypointsGmaps.count - 1)) tratti da calcolare",
                status: vm.routingStatus
            )
            PrepStepRow(
                icon: "internaldrive.fill",
                title: "Salvataggio offline",
                subtitle: "Disponibile senza connessione",
                status: vm.cachingStatus
            )
        }
    }

    @ViewBuilder
    private var bottomSection: some View {
        if let err = vm.error {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: { Task { await vm.prepare(route: route) } }) {
                    Label("Riprova", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

        } else if let navRoute = vm.navigationRoute {
            NavigationLink(destination: NavigatorView(navRoute: navRoute, motoRoute: route)) {
                Label("Inizia navigazione", systemImage: "location.north.fill")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }
}

// MARK: - Step Row

enum StepStatus {
    case waiting, inProgress, done, failed
}

struct PrepStepRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: StepStatus

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(circleColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                if status == .inProgress {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(circleColor)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(circleColor)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var circleColor: Color {
        switch status {
        case .waiting:    return .gray
        case .inProgress: return .orange
        case .done:       return .green
        case .failed:     return .red
        }
    }

    private var statusIcon: String {
        switch status {
        case .waiting:    return icon
        case .inProgress: return icon
        case .done:       return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        }
    }

    private var statusSubtitle: String {
        switch status {
        case .waiting:    return subtitle
        case .inProgress: return "In corso…"
        case .done:       return "Completato"
        case .failed:     return "Errore — tocca Riprova"
        }
    }
}
