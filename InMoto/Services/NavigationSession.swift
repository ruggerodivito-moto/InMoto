import Foundation
import CoreLocation
import AVFoundation

/// Sessione di navigazione attiva. Tutto l'avanzamento (tappe, manovre, arrivo)
/// deriva dal map matching della posizione GPS sul percorso (RouteGeometry):
/// non serve mai toccare il telefono — tappe raggiunte, tappe saltate e ripresa
/// a metà percorso vengono gestite automaticamente dalla progressione in metri.
@MainActor
final class NavigationSession: ObservableObject {

    struct UpcomingTurn: Equatable {
        let key: Int
        let coordinate: CLLocationCoordinate2D
        let direction: TurnDirection
        let instruction: String
        let isPrimary: Bool
        static func == (l: Self, r: Self) -> Bool { l.key == r.key }
    }

    // MARK: - Stato osservato dalla UI

    @Published private(set) var navRoute: NavigationRoute
    @Published private(set) var routeVersion = 0          // incrementa a ogni ricalcolo
    @Published private(set) var currentLegIndex = 0
    @Published private(set) var arrivedAtDestination = false
    @Published private(set) var distanceToNextWaypoint: Double = 0  // metri lungo il percorso
    @Published private(set) var distanceToNextStep: Double = 0      // metri lungo il percorso
    @Published private(set) var matchedPointIndex = 0
    @Published private(set) var isOffRoute = false
    @Published private(set) var isRerouting = false
    @Published private(set) var upcomingStepIdx: Int?

    private(set) var geometry: RouteGeometry

    // MARK: - Stato interno di matching

    private var progressMeters: Double = 0
    private var lastMatchPointIndex: Int?
    private var hasInitialFix = false
    private var hasAnnouncedStart = false
    private var offRouteFixCount = 0
    private var lastRerouteAttempt: Date?
    private var announcedRerouteFailure = false

    private let offRouteDistance: Double = 70   // metri dalla linea
    private let offRouteFixesNeeded = 3
    private let rerouteCooldown: TimeInterval = 25

    // MARK: - Voce

    private let synthesizer = AVSpeechSynthesizer()
    private var announcedEarly: Set<Int> = []
    private var announcedNow: Set<Int> = []
    private var hasAnnouncedArrival = false

    init(navRoute: NavigationRoute) {
        self.navRoute = navRoute
        self.geometry = RouteGeometry(route: navRoute)
    }

    // MARK: - Audio (auricolare Bluetooth, schermo spento, interruttore silenzioso)

    /// Senza una sessione .playback attiva la sintesi vocale viene silenziata
    /// dall'interruttore laterale e non è garantita a schermo spento.
    func beginAudio() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? s.setActive(true)
    }

    func endAudio() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Aggiornamento GPS

    func update(userLocation loc: CLLocation) {
        guard !arrivedAtDestination else { return }
        guard let m = geometry.match(loc.coordinate,
                                     nearPointIndex: lastMatchPointIndex,
                                     minProgress: progressMeters - 300) else { return }

        // Fuori percorso: tollera fix imprecisi, poi ricalcola
        let tolerance = max(offRouteDistance, loc.horizontalAccuracy * 1.5)
        guard m.distanceFromRoute <= tolerance else {
            offRouteFixCount += 1
            if offRouteFixCount >= offRouteFixesNeeded {
                isOffRoute = true
                requestReroute(from: loc)
            }
            return
        }

        offRouteFixCount = 0
        isOffRoute = false
        announcedRerouteFailure = false
        lastMatchPointIndex = m.pointIndex
        matchedPointIndex = m.pointIndex

        let firstFix = !hasInitialFix
        hasInitialFix = true
        if firstFix {
            // Aggancio iniziale: anche a metà percorso (ripresa dopo una sosta)
            // senza annunciare le tappe già superate
            progressMeters = m.progress
            if !hasAnnouncedStart {
                hasAnnouncedStart = true
                let dest = shortName(navRoute.waypoints.last?.name ?? "destinazione")
                speak("Navigazione avviata verso \(dest).")
            }
        } else if m.progress > progressMeters || progressMeters - m.progress < 300 {
            // La progressione può arretrare solo di poco (rumore GPS);
            // i salti in avanti sono sempre accettati (tappe saltate incluse)
            progressMeters = m.progress
        }

        syncLeg(announce: !firstFix)
        updateStep(speed: loc.speed)
        updateDistances()
        checkArrival(loc)
    }

    // MARK: - Avanzamento tappe

    private func syncLeg(announce: Bool) {
        let newLeg = geometry.legIndex(forProgress: progressMeters)
        guard newLeg != currentLegIndex else { return }
        if newLeg > currentLegIndex, announce {
            let nextIdx = min(newLeg + 1, navRoute.waypoints.count - 1)
            speak("Tappa raggiunta. Prossima destinazione: \(shortName(navRoute.waypoints[nextIdx].name)).")
        }
        currentLegIndex = newLeg
    }

    // MARK: - Manovre e annunci vocali

    private func updateStep(speed: Double) {
        guard let idx = geometry.upcomingStepIndex(afterProgress: progressMeters) else {
            upcomingStepIdx = nil
            distanceToNextStep = 0
            return
        }
        upcomingStepIdx = idx
        let step = geometry.steps[idx]
        distanceToNextStep = step.progress - progressMeters

        // Annunci basati sul tempo alla manovra, non su soglie fisse:
        // a 100 km/h "tra 200 metri" arriverebbe troppo tardi
        let v = speed > 1 ? speed : 13                  // fermo/sconosciuto: ~47 km/h
        let nowDist   = min(280, max(60, v * 7))        // ~7 secondi prima
        let earlyDist = min(1300, max(320, v * 25))     // ~25 secondi prima

        if distanceToNextStep < nowDist {
            if !announcedNow.contains(idx) {
                announcedNow.insert(idx)
                announcedEarly.insert(idx)
                speak(step.instruction)
            }
        } else if distanceToNextStep < earlyDist, !announcedEarly.contains(idx) {
            announcedEarly.insert(idx)
            speak("Tra \(voiceDistance(distanceToNextStep)), \(step.instruction)")
        }
    }

    private func updateDistances() {
        let nextWp = min(currentLegIndex + 1, geometry.waypointProgress.count - 1)
        distanceToNextWaypoint = max(0, geometry.waypointProgress[nextWp] - progressMeters)
    }

    private func checkArrival(_ loc: CLLocation) {
        guard !hasAnnouncedArrival else { return }
        let remaining = geometry.totalMeters - progressMeters
        let direct: Double = navRoute.waypoints.last.map {
            loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        } ?? .infinity
        if remaining < 40 || (direct < 60 && currentLegIndex == navRoute.legs.count - 1) {
            hasAnnouncedArrival = true
            arrivedAtDestination = true
            speak("Sei arrivato a destinazione. Buona moto!")
        }
    }

    // MARK: - Ricalcolo fuori percorso

    private func requestReroute(from loc: CLLocation) {
        guard !isRerouting else { return }
        if let last = lastRerouteAttempt, Date().timeIntervalSince(last) < rerouteCooldown { return }
        lastRerouteAttempt = Date()
        isRerouting = true

        // Obiettivo: la prossima tappa non ancora raggiunta. Se non siamo mai
        // davvero partiti, puntiamo alla partenza del percorso.
        let notStarted = !hasInitialFix || progressMeters < 250
        let targetIdx = notStarted ? 0 : min(currentLegIndex + 1, navRoute.waypoints.count - 1)
        let target = navRoute.waypoints[targetIdx]

        Task {
            do {
                let connector = try await RouterService.shared.connectorLeg(
                    from: loc.coordinate, to: target)
                applyReroute(connector: connector, targetWaypointIndex: targetIdx, location: loc)
            } catch {
                isRerouting = false
                if !announcedRerouteFailure {
                    announcedRerouteFailure = true
                    speak("Sei fuori percorso e non riesco a ricalcolare. Rientra sul tracciato.")
                }
            }
        }
    }

    private func applyReroute(connector: RouteLeg, targetWaypointIndex: Int, location: CLLocation) {
        var waypoints = navRoute.waypoints
        var legs = navRoute.legs
        let here = GeocodedWaypoint(name: "Posizione attuale",
                                    latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude)

        if targetWaypointIndex == 0 {
            // Non ancora partiti: tratta di avvicinamento prima della partenza
            waypoints.insert(here, at: 0)
            legs.insert(connector, at: 0)
        } else {
            // Sostituisci la tratta corrente: posizione attuale → prossima tappa
            waypoints[targetWaypointIndex - 1] = here
            legs[targetWaypointIndex - 1] = connector
        }

        navRoute = NavigationRoute(routeId: navRoute.routeId,
                                   routeName: navRoute.routeName,
                                   waypoints: waypoints,
                                   legs: legs)
        geometry = RouteGeometry(route: navRoute)

        // Riaggancio sul nuovo percorso al prossimo fix (senza ri-annunciare l'avvio)
        lastMatchPointIndex = nil
        hasInitialFix = false
        progressMeters = 0
        currentLegIndex = max(0, targetWaypointIndex - 1)
        announcedEarly = []
        announcedNow = []
        offRouteFixCount = 0
        isOffRoute = false
        isRerouting = false
        routeVersion += 1
        speak("Percorso ricalcolato.")
    }

    // MARK: - Valori per la UI

    var routePoints: [CLLocationCoordinate2D] { geometry.points }

    var currentInstruction: String {
        if arrivedAtDestination { return "Destinazione raggiunta" }
        if let idx = upcomingStepIdx, idx < geometry.steps.count {
            return geometry.steps[idx].instruction
        }
        guard currentLegIndex < navRoute.legs.count else { return "Destinazione raggiunta" }
        return "Prosegui verso \(shortName(navRoute.legs[currentLegIndex].toName))"
    }

    /// Prossime 2 manovre da mostrare sulla mappa
    var upcomingTurns: [UpcomingTurn] {
        guard let start = upcomingStepIdx else { return [] }
        var out: [UpcomingTurn] = []
        var i = start
        while i < geometry.steps.count, out.count < 2 {
            let s = geometry.steps[i]
            let dir = TurnDirection.parse(s.instruction)
            if dir != .straight || i == start {
                out.append(UpcomingTurn(key: routeVersion * 100_000 + i,
                                        coordinate: s.coordinate, direction: dir,
                                        instruction: s.instruction, isPrimary: out.isEmpty))
            }
            i += 1
        }
        return out
    }

    var nextWaypointName: String {
        let idx = min(currentLegIndex + 1, navRoute.waypoints.count - 1)
        return shortName(navRoute.waypoints[idx].name)
    }

    var progressText: String {
        "Tappa \(currentLegIndex + 1) / \(navRoute.legs.count + 1)"
    }

    var etaCurrentLeg: String {
        guard currentLegIndex < navRoute.legs.count else { return "" }
        let legStart = geometry.waypointProgress[currentLegIndex]
        let legEnd = geometry.waypointProgress[currentLegIndex + 1]
        let legLen = max(1, legEnd - legStart)
        let fraction = min(1, max(0, (legEnd - progressMeters) / legLen))
        let mins = max(0, Int(navRoute.legs[currentLegIndex].durationSeconds * fraction) / 60)
        return mins < 60 ? "\(mins) min" : "\(mins / 60)h \(mins % 60)min"
    }

    var formattedDistance: String {
        formatMeters(distanceToNextWaypoint)
    }

    var remainingFormatted: String {
        formatMeters(max(0, geometry.totalMeters - progressMeters))
    }

    var progressFraction: Double {
        geometry.totalMeters > 0 ? min(1, progressMeters / geometry.totalMeters) : 0
    }

    // MARK: - Private helpers

    private func formatMeters(_ m: Double) -> String {
        if m < 1000 { return String(format: "%.0f m", m) }
        return String(format: "%.1f km", m / 1000)
    }

    private func voiceDistance(_ meters: Double) -> String {
        if meters < 950 {
            let rounded = max(100, Int((meters / 100).rounded()) * 100)
            return "\(rounded) metri"
        }
        let km = meters / 1000
        if km < 1.5 { return "un chilometro" }
        return "\(Int(km.rounded())) chilometri"
    }

    private func speak(_ text: String) {
        // Accoda senza interrompere l'annuncio in corso
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "it-IT")
        utt.rate = 0.52
        synthesizer.speak(utt)
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }
}
