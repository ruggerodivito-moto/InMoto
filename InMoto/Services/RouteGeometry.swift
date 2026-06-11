import Foundation
import CoreLocation

/// Geometria "appiattita" di una NavigationRoute: tutte le tratte in un unico
/// polyline con distanze progressive. È la base del map matching: la posizione
/// GPS viene proiettata sulla linea e l'avanzamento (tappe, step, annunci)
/// deriva dalla progressione in metri lungo il percorso, mai da soglie puntuali
/// che in moto si saltano facilmente.
struct RouteGeometry {

    struct FlatStep {
        let legIndex: Int
        let progress: Double                    // metri dall'inizio del percorso
        let instruction: String
        let coordinate: CLLocationCoordinate2D
    }

    struct Match {
        let pointIndex: Int                     // primo punto del segmento agganciato
        let coordinate: CLLocationCoordinate2D  // proiezione sulla linea
        let progress: Double                    // metri dall'inizio
        let distanceFromRoute: Double           // distanza perpendicolare dalla linea
    }

    let points: [CLLocationCoordinate2D]
    let cumulative: [Double]        // metri dall'inizio, per ogni punto
    let waypointProgress: [Double]  // metri dall'inizio, per ogni waypoint
    let steps: [FlatStep]           // ordinati per progress

    var totalMeters: Double { cumulative.last ?? 0 }

    init(route: NavigationRoute) {
        var pts: [CLLocationCoordinate2D] = []
        var cum: [Double] = []
        var wpProg: [Double] = [0]
        var legRanges: [ClosedRange<Int>] = []

        for leg in route.legs {
            let firstIdx = max(0, pts.count - 1)
            for c in leg.polylineCoordinates {
                // Le tratte consecutive condividono il punto di giunzione: salta i duplicati
                if let last = pts.last,
                   abs(last.latitude - c.latitude) < 1e-7,
                   abs(last.longitude - c.longitude) < 1e-7 { continue }
                if let last = pts.last {
                    cum.append(cum[cum.count - 1] + Self.distance(last, c))
                } else {
                    cum.append(0)
                }
                pts.append(c)
            }
            legRanges.append(firstIdx...max(firstIdx, pts.count - 1))
            wpProg.append(cum.last ?? 0)
        }

        var flat: [FlatStep] = []
        for (li, leg) in route.legs.enumerated() {
            let range = legRanges[li]
            for step in leg.steps {
                let prog: Double
                if range.lowerBound < range.upperBound,
                   let m = Self.bestMatch(step.coordinate, points: pts, cumulative: cum,
                                          segments: range.lowerBound..<range.upperBound) {
                    prog = m.progress
                } else {
                    prog = wpProg[li]
                }
                flat.append(FlatStep(legIndex: li, progress: prog,
                                     instruction: step.instruction,
                                     coordinate: step.coordinate))
            }
        }
        flat.sort { $0.progress < $1.progress }

        self.points = pts
        self.cumulative = cum
        self.waypointProgress = wpProg
        self.steps = flat
    }

    /// Proietta una coordinata sul percorso. Cerca prima in una finestra attorno
    /// all'ultimo aggancio (evita di saltare su tratti vicini ma futuri/passati,
    /// es. anelli o nodi in comune tra tragitti); se fallisce estende la ricerca
    /// a tutto il percorso preferendo agganci coerenti con la progressione fatta.
    func match(_ coordinate: CLLocationCoordinate2D,
               nearPointIndex: Int?,
               minProgress: Double) -> Match? {
        guard points.count >= 2 else { return nil }
        let lastPoint = points.count - 1

        if let i = nearPointIndex {
            let lo = max(0, i - 40)
            let hi = min(lastPoint, i + 400)
            if lo < hi,
               let m = Self.bestMatch(coordinate, points: points, cumulative: cumulative,
                                      segments: lo..<hi),
               m.distanceFromRoute < 70 {
                return m
            }
        }

        // Ricerca "in avanti": solo sui tratti non ancora superati
        if minProgress > 0 {
            let startIdx = cumulative.firstIndex { $0 >= minProgress } ?? 0
            if startIdx < lastPoint,
               let m = Self.bestMatch(coordinate, points: points, cumulative: cumulative,
                                      segments: startIdx..<lastPoint),
               m.distanceFromRoute < 70 {
                return m
            }
        }

        return Self.bestMatch(coordinate, points: points, cumulative: cumulative,
                              segments: 0..<lastPoint)
    }

    /// Indice della tratta corrente data la progressione (un nodo conta come
    /// raggiunto già `reachThreshold` metri prima, per annunciare in tempo)
    func legIndex(forProgress p: Double, reachThreshold: Double = 30) -> Int {
        guard waypointProgress.count > 2 else { return 0 }
        var idx = 0
        for j in 1..<(waypointProgress.count - 1) where p + reachThreshold >= waypointProgress[j] {
            idx = j
        }
        return idx
    }

    /// Prossima manovra non ancora superata
    func upcomingStepIndex(afterProgress p: Double) -> Int? {
        steps.firstIndex { $0.progress > p + 8 }
    }

    // MARK: - Helpers geometrici

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func bestMatch(_ c: CLLocationCoordinate2D,
                                  points: [CLLocationCoordinate2D],
                                  cumulative: [Double],
                                  segments: Range<Int>) -> Match? {
        guard !segments.isEmpty else { return nil }
        // Proiezione planare locale: sufficiente per distanze di pochi km
        let kLat = 111_132.0
        let kLon = 111_320.0 * cos(c.latitude * .pi / 180)

        var best: Match?
        for i in segments {
            let a = points[i], b = points[i + 1]
            let ax = (a.longitude - c.longitude) * kLon
            let ay = (a.latitude  - c.latitude)  * kLat
            let bx = (b.longitude - c.longitude) * kLon
            let by = (b.latitude  - c.latitude)  * kLat
            let dx = bx - ax, dy = by - ay
            let lenSq = dx * dx + dy * dy
            let t = lenSq > 0 ? min(1, max(0, -(ax * dx + ay * dy) / lenSq)) : 0
            let px = ax + dx * t, py = ay + dy * t
            let dist = (px * px + py * py).squareRoot()
            if best == nil || dist < best!.distanceFromRoute {
                best = Match(
                    pointIndex: i,
                    coordinate: CLLocationCoordinate2D(
                        latitude:  a.latitude  + (b.latitude  - a.latitude)  * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t),
                    progress: cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t,
                    distanceFromRoute: dist)
            }
        }
        return best
    }
}
