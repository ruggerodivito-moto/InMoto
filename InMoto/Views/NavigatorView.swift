import SwiftUI
import CoreLocation

struct NavigatorView: View {
    let motoRoute: MotoRoute

    @StateObject private var session: NavigationSession
    @ObservedObject private var locationMgr = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showArrivalAlert = false
    @State private var isFollowingUser = false        // overview all'avvio
    @State private var hasStartedNavigation = false   // true dopo tap "Avvia"

    init(navRoute: NavigationRoute, motoRoute: MotoRoute) {
        self.motoRoute = motoRoute
        _session = StateObject(wrappedValue: NavigationSession(navRoute: navRoute))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Mappa a tutto schermo: percorso futuro davanti, già percorso in grigio
            MapKitView(
                navRoute: session.navRoute,
                routeVersion: session.routeVersion,
                routePoints: session.routePoints,
                matchedPointIndex: session.matchedPointIndex,
                currentLegIndex: session.currentLegIndex,
                upcomingTurns: session.upcomingTurns,
                userLocation: locationMgr.location,
                userHeading: locationMgr.heading?.trueHeading,
                isFollowingUser: $isFollowingUser
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Riepilogo tappa/ETA/rimanente in alto: in basso gli angoli
                // arrotondati dell'iPhone tagliavano le scritte
                progressHeader
                instructionBanner
                if session.isRerouting || session.isOffRoute {
                    rerouteBanner
                }
                Spacer()
            }

            // Pulsante avvia (prima volta) o ricentra (dopo aver avviato)
            if !hasStartedNavigation {
                startButton
            } else if !isFollowingUser {
                recenterButton
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { session.isMuted.toggle() }) {
                    Image(systemName: session.isMuted ? "speaker.slash.circle.fill"
                                                      : "speaker.wave.2.circle.fill")
                        .font(.title2)
                        .foregroundStyle(session.isMuted ? .red : .white)
                        .shadow(radius: 3)
                }
                .accessibilityLabel(session.isMuted ? "Riattiva voce" : "Disattiva voce")
            }
        }
        .onAppear {
            locationMgr.requestPermission()   // chiede permesso subito
            // il GPS parte solo quando l'utente tocca "Avvia navigazione GPS"
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            locationMgr.stop()
            session.endAudio()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(locationMgr.$location.compactMap { $0 }) { loc in
            guard hasStartedNavigation else { return }
            session.update(userLocation: loc)
        }
        .onChange(of: session.arrivedAtDestination) { arrived in
            if arrived { showArrivalAlert = true }
        }
        .alert("Sei arrivato!", isPresented: $showArrivalAlert) {
            Button("Chiudi navigazione") { dismiss() }
        } message: {
            Text("Hai completato l'itinerario \(motoRoute.nome). Buona moto!")
        }
    }

    // MARK: - Pulsante avvia navigazione (overview → GPS 3D)

    private var startButton: some View {
        VStack {
            Spacer()
            Button(action: {
                hasStartedNavigation = true
                isFollowingUser = true
                session.beginAudio()
                locationMgr.start()
            }) {
                Label("Avvia navigazione GPS", systemImage: "location.north.fill")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4), value: hasStartedNavigation)
    }

    // MARK: - Pulsante ricentra

    private var recenterButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { isFollowingUser = true }) {
                    Image(systemName: "location.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 44)
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3), value: isFollowingUser)
    }

    // MARK: - Banner istruzioni (in alto)

    private var currentTurnDirection: TurnDirection {
        TurnDirection.parse(session.currentInstruction)
    }

    private var instructionBanner: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Freccia direzionale dinamica
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange)
                        .frame(width: 52, height: 52)
                    Image(systemName: currentTurnDirection.sfSymbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.currentInstruction)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if session.distanceToNextStep > 0 {
                        Text(formatStep(session.distanceToNextStep))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.black.opacity(0.80))

            // Barra destinazione prossima tappa
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.orange)
                Text(session.nextWaypointName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(session.formattedDistance)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    // MARK: - Banner ricalcolo / fuori percorso

    private var rerouteBanner: some View {
        HStack(spacing: 8) {
            if session.isRerouting {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                Text("Ricalcolo percorso…")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Fuori percorso")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.95))
    }

    // MARK: - Riepilogo progresso (in alto, sopra le indicazioni)

    private var progressHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Tappa corrente
                VStack(spacing: 2) {
                    Text(session.progressText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(shortName(session.navRoute.waypoints[session.currentLegIndex].name))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // ETA tratta
                VStack(spacing: 2) {
                    Text("ETA tappa")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(session.etaCurrentLeg)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Distanza totale rimanente
                VStack(spacing: 2) {
                    Text("Rimanente")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(session.remainingFormatted)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(.regularMaterial)

            // Barra avanzamento continua (metri percorsi / totali)
            progressBar
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                Rectangle()
                    .fill(Color.orange)
                    .frame(
                        width: geo.size.width * session.progressFraction,
                        height: 4
                    )
                    .animation(.easeInOut, value: session.progressFraction)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Computed helpers

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }

    private func formatStep(_ meters: Double) -> String {
        if meters < 50   { return "Ora" }
        if meters < 200  { return "Tra \(Int((meters / 10).rounded()) * 10) m" }
        if meters < 1000 { return "Tra \(Int((meters / 100).rounded()) * 100) m" }
        return String(format: "Tra %.1f km", meters / 1000)
    }
}
