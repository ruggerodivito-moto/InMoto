import SwiftUI
import CoreLocation
import AVFoundation

// MARK: - NavigationSession

@MainActor
class NavigationSession: ObservableObject {
    @Published var currentLegIndex: Int = 0
    @Published var currentStepIndex: Int = 0
    @Published var arrivedAtDestination: Bool = false
    @Published var distanceToNextWaypoint: Double = 0   // metri
    @Published var distanceToNextStep: Double = 0       // metri

    let navRoute: NavigationRoute
    private let arrivalThreshold: Double = 150          // metri
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenStepIndex: Int = -1
    private var hasAnnouncedArrival: Bool = false

    init(navRoute: NavigationRoute) {
        self.navRoute = navRoute
    }

    // Chiamato ad ogni aggiornamento GPS
    func update(userLocation: CLLocation) {
        guard !arrivedAtDestination, currentLegIndex < navRoute.legs.count else { return }

        let target = navRoute.waypoints[currentLegIndex + 1]
        let targetLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
        distanceToNextWaypoint = userLocation.distance(from: targetLoc)

        // Prossimo step della tratta corrente
        if currentLegIndex < navRoute.legs.count {
            let leg = navRoute.legs[currentLegIndex]
            if currentStepIndex < leg.steps.count {
                let step = leg.steps[currentStepIndex]
                let stepLoc = CLLocation(latitude: step.latitude, longitude: step.longitude)
                distanceToNextStep = userLocation.distance(from: stepLoc)

                // Annuncia istruzione quando sei a meno di 200m dallo step
                if distanceToNextStep < 200, lastSpokenStepIndex != currentStepIndex {
                    speak(step.instruction)
                    lastSpokenStepIndex = currentStepIndex
                }

                // Passa allo step successivo quando sei a meno di 30m
                if distanceToNextStep < 30, currentStepIndex + 1 < leg.steps.count {
                    currentStepIndex += 1
                }
            }
        }

        // Controllo arrivo alla tappa successiva
        if distanceToNextWaypoint < arrivalThreshold {
            let nextWpIndex = currentLegIndex + 1
            if nextWpIndex < navRoute.waypoints.count - 1 {
                // Tappa intermedia raggiunta → avanza
                let nextName = shortName(navRoute.waypoints[nextWpIndex + 1].name)
                speak("Tappa raggiunta. Prossima destinazione: \(nextName)")
                currentLegIndex += 1
                currentStepIndex = 0
                lastSpokenStepIndex = -1
            } else if nextWpIndex == navRoute.waypoints.count - 1 {
                // Destinazione finale
                if !hasAnnouncedArrival {
                    speak("Sei arrivato a destinazione. Buona moto!")
                    hasAnnouncedArrival = true
                    arrivedAtDestination = true
                }
            }
        }
    }

    var currentInstruction: String {
        guard currentLegIndex < navRoute.legs.count else { return "Destinazione raggiunta" }
        let leg = navRoute.legs[currentLegIndex]
        guard currentStepIndex < leg.steps.count else {
            return "Prosegui verso \(shortName(leg.toName))"
        }
        return leg.steps[currentStepIndex].instruction
    }

    var nextWaypointName: String {
        let idx = min(currentLegIndex + 1, navRoute.waypoints.count - 1)
        return shortName(navRoute.waypoints[idx].name)
    }

    var progressText: String {
        let done = currentLegIndex
        let total = navRoute.legs.count
        return "Tappa \(done + 1) / \(total + 1)"
    }

    var etaCurrentLeg: String {
        guard currentLegIndex < navRoute.legs.count else { return "" }
        let secs = navRoute.legs[currentLegIndex].durationSeconds
        let m = Int(secs) / 60
        return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)min"
    }

    var formattedDistance: String {
        if distanceToNextWaypoint < 1000 {
            return String(format: "%.0f m", distanceToNextWaypoint)
        }
        return String(format: "%.1f km", distanceToNextWaypoint / 1000)
    }

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "it-IT")
        utt.rate = 0.52
        synthesizer.speak(utt)
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }
}

// MARK: - NavigatorView

struct NavigatorView: View {
    let navRoute: NavigationRoute
    let motoRoute: MotoRoute

    @StateObject private var session: NavigationSession
    @ObservedObject private var locationMgr = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showArrivalAlert = false
    @State private var isFollowingUser = true

    init(navRoute: NavigationRoute, motoRoute: MotoRoute) {
        self.navRoute = navRoute
        self.motoRoute = motoRoute
        _session = StateObject(wrappedValue: NavigationSession(navRoute: navRoute))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Mappa a tutto schermo con vista in primo piano
            MapKitView(
                navRoute: navRoute,
                currentLegIndex: session.currentLegIndex,
                currentStepIndex: session.currentStepIndex,
                userLocation: locationMgr.location,
                userHeading: locationMgr.heading?.trueHeading,
                isFollowingUser: $isFollowingUser
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                instructionBanner
                Spacer()
                progressFooter
            }
            .ignoresSafeArea(edges: .bottom)

            // Pulsante ricentra — compare quando l'utente sposta la mappa manualmente
            if !isFollowingUser {
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
        }
        .onAppear {
            locationMgr.requestPermission()
            locationMgr.start()
            UIApplication.shared.isIdleTimerDisabled = true  // schermo sempre acceso
        }
        .onDisappear {
            locationMgr.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(locationMgr.$location.compactMap { $0 }) { loc in
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
                .padding(.bottom, 130)   // sopra il footer di navigazione
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

    // MARK: - Footer progresso (in basso)

    private var progressFooter: some View {
        VStack(spacing: 0) {
            // Barra progresso tappe
            progressBar

            HStack(spacing: 0) {
                // Tappa corrente
                VStack(spacing: 2) {
                    Text(session.progressText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(shortName(navRoute.waypoints[session.currentLegIndex].name))
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
                    Text(remainingDistance)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(.regularMaterial)
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
                        width: geo.size.width * progress,
                        height: 4
                    )
                    .animation(.easeInOut, value: session.currentLegIndex)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Computed helpers

    private var progress: Double {
        guard navRoute.legs.count > 0 else { return 0 }
        return Double(session.currentLegIndex) / Double(navRoute.legs.count)
    }

    private var remainingDistance: String {
        let done = navRoute.legs.prefix(session.currentLegIndex).reduce(0) { $0 + $1.distanceMeters }
        let remaining = max(0, navRoute.totalDistanceMeters - done)
        if remaining < 1000 { return String(format: "%.0f m", remaining) }
        return String(format: "%.0f km", remaining / 1000)
    }

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
