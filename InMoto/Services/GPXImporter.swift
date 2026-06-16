import Foundation
import CoreLocation

/// Importa una traccia GPX (Garmin, Strava, Komoot…) e la trasforma in un
/// percorso navigabile che segue **esattamente** il tracciato registrato: i
/// punti della traccia diventano la polyline di navigazione, senza alcun
/// ricalcolo stradale (niente geocoding, niente MKDirections).
///
/// La `NavigationRoute` prodotta va salvata in cache con `routeId` = id del
/// `MotoRoute`: `DownloadPreparationView` la riusa dalla cache e il motore di
/// navigazione (RouteGeometry/NavigationSession) la consuma senza modifiche.
struct GPXImporter {

    struct ParsedTrack {
        let name: String
        let points: [CLLocationCoordinate2D]
    }

    enum GPXError: LocalizedError {
        case noPoints
        case invalid
        var errorDescription: String? {
            switch self {
            case .noPoints: return "Il file GPX non contiene una traccia con punti sufficienti."
            case .invalid:  return "File GPX non valido o illeggibile."
            }
        }
    }

    // MARK: - Parsing

    static func parse(data: Data, fallbackName: String) throws -> ParsedTrack {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.invalid }

        let pts = delegate.bestPoints
        guard pts.count >= 2 else { throw GPXError.noPoints }

        let parsedName = delegate.trackName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = parsedName.isEmpty ? fallbackName : parsedName
        return ParsedTrack(name: name, points: pts)
    }

    // MARK: - Costruzione percorso navigabile

    /// Crea il `MotoRoute` personale e la `NavigationRoute` "esatta" già pronta.
    /// Restituisce entrambi: salvare il primo in `RouteStore` e mettere in cache
    /// la seconda con `RouterService.cacheRoute` (routeId condiviso).
    static func buildRoute(from track: ParsedTrack, displayName: String) -> (route: MotoRoute, navRoute: NavigationRoute) {
        let pts = track.points
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? track.name : trimmed

        // Distanze cumulative lungo la traccia (metri dall'inizio per ogni punto)
        var cum: [Double] = [0]
        for i in 1..<pts.count {
            cum.append(cum[i - 1] + RouteGeometry.distance(pts[i - 1], pts[i]))
        }
        let total = cum.last ?? 0
        let totalKm = total / 1000

        // La traccia continua viene spezzata in più tratte: dà progressione/ETA
        // per tappa ed evita il falso "arrivo" sugli anelli (partenza ≈ arrivo),
        // dove una singola tratta farebbe scattare l'arrivo già alla partenza.
        let segCount = max(2, min(8, Int((totalKm / 4).rounded())))

        // Indici di taglio a frazioni uguali della distanza totale
        var splitIdx: [Int] = [0]
        for s in 1..<segCount {
            let target = total * Double(s) / Double(segCount)
            let idx = cum.firstIndex { $0 >= target } ?? (pts.count - 1)
            if idx > splitIdx.last! { splitIdx.append(idx) }
        }
        if splitIdx.last! != pts.count - 1 { splitIdx.append(pts.count - 1) }

        // Un waypoint per ogni confine di tratta (servono a ETA, annunci, reroute)
        var waypoints: [GeocodedWaypoint] = []
        for (k, idx) in splitIdx.enumerated() {
            let label: String
            if k == 0 {
                label = "Partenza"
            } else if k == splitIdx.count - 1 {
                label = name
            } else {
                label = "km \(Int((cum[idx] / 1000).rounded()))"
            }
            waypoints.append(GeocodedWaypoint(name: label,
                                              latitude: pts[idx].latitude,
                                              longitude: pts[idx].longitude))
        }

        // Tratte: sotto-polyline tra confini consecutivi (estremo condiviso, che
        // RouteGeometry deduplica come fa per le tratte di MKDirections)
        let avgSpeedKmh = 45.0   // stima su strade miste (la traccia non ha tempi)
        var legs: [RouteLeg] = []
        for i in 0..<(splitIdx.count - 1) {
            let a = splitIdx[i], b = splitIdx[i + 1]
            let slice = Array(pts[a...b])
            let legMeters = cum[b] - cum[a]
            let legSeconds = legMeters / 1000 / avgSpeedKmh * 3600
            legs.append(RouteLeg(fromName: waypoints[i].name,
                                 toName: waypoints[i + 1].name,
                                 distanceMeters: legMeters,
                                 durationSeconds: legSeconds,
                                 polylineCoordinates: slice,
                                 steps: synthesizeSteps(points: slice)))
        }

        let routeId = UUID().uuidString
        let navRoute = NavigationRoute(routeId: routeId, routeName: name,
                                       waypoints: waypoints, legs: legs)

        let route = MotoRoute(
            id: routeId,
            nome: name,
            partenza: "Partenza", arrivo: name,
            regione: "",
            km: max(1, Int(totalKm.rounded())),
            durataMin: max(1, Int(total / 1000 / avgSpeedKmh * 60)),
            difficolta: "Media", stelle: 0,
            descrizione: "Traccia GPX importata · \(pts.count) punti · segue esattamente il tracciato registrato.",
            tappe: waypoints.map { $0.name },
            waypointsGmaps: waypoints.map { "\($0.latitude),\($0.longitude)" },
            tags: ["gpx", "personale"],
            fonte: "GPX importato", stagione: "Tutto l'anno", isCustom: true,
            legKm: legs.map { max(1, Int($0.distanceMeters / 1000)) },
            legMin: legs.map { max(1, Int($0.durationSeconds / 60)) }
        )
        return (route, navRoute)
    }

    // MARK: - Manovre sintetizzate

    /// La traccia non ha metadati di svolta: le manovre (frecce + voce) si
    /// stimano dai cambi di rotta su una versione semplificata del tracciato
    /// (Douglas–Peucker), così da ignorare il rumore GPS.
    private static func synthesizeSteps(points: [CLLocationCoordinate2D]) -> [RouteStep] {
        guard points.count >= 3 else { return [] }
        let simplified = douglasPeucker(points, epsilon: 18)
        guard simplified.count >= 3 else { return [] }

        var steps: [RouteStep] = []
        for i in 1..<(simplified.count - 1) {
            let inBearing  = bearing(simplified[i - 1], simplified[i])
            let outBearing = bearing(simplified[i], simplified[i + 1])
            var delta = outBearing - inBearing
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            let mag = abs(delta)
            guard mag >= 30 else { continue }      // sotto i 30° è "prosegui"

            let right = delta > 0                  // bearing orario: +Δ = a destra
            let instruction: String
            switch mag {
            case 30..<50:   instruction = right ? "Leggermente a destra" : "Leggermente a sinistra"
            case 50..<115:  instruction = right ? "Gira a destra" : "Gira a sinistra"
            case 115..<165: instruction = right ? "Svolta secca a destra" : "Svolta secca a sinistra"
            default:        instruction = "Fai inversione di marcia"
            }
            steps.append(RouteStep(instruction: instruction, distanceMeters: 0,
                                   coordinate: simplified[i]))
        }
        return steps
    }

    // MARK: - Helpers geometrici

    private static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    /// Semplificazione Douglas–Peucker (epsilon in metri, proiezione planare locale)
    private static func douglasPeucker(_ pts: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (s, e) = stack.popLast() {
            guard e > s + 1 else { continue }
            var maxD = 0.0, idx = -1
            for i in (s + 1)..<e {
                let d = perpDistance(pts[i], pts[s], pts[e])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > epsilon, idx != -1 {
                keep[idx] = true
                stack.append((s, idx))
                stack.append((idx, e))
            }
        }
        return pts.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// Distanza perpendicolare del punto `p` dalla retta passante per `a` e `b`
    private static func perpDistance(_ p: CLLocationCoordinate2D,
                                     _ a: CLLocationCoordinate2D,
                                     _ b: CLLocationCoordinate2D) -> Double {
        let kLat = 111_132.0
        let kLon = 111_320.0 * cos(p.latitude * .pi / 180)
        let ax = (a.longitude - p.longitude) * kLon, ay = (a.latitude - p.latitude) * kLat
        let bx = (b.longitude - p.longitude) * kLon, by = (b.latitude - p.latitude) * kLat
        let dx = bx - ax, dy = by - ay
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-6 { return (ax * ax + ay * ay).squareRoot() }
        // p è l'origine: distanza origine→retta(a,b) = |(b-a) × a| / |b-a|
        return abs(dx * ay - dy * ax) / len
    }
}

// MARK: - XMLParser delegate

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var trkpts: [CLLocationCoordinate2D] = []
    private var rtepts: [CLLocationCoordinate2D] = []
    private var wpts:   [CLLocationCoordinate2D] = []

    private(set) var trackName: String?
    private var capturingName = false
    private var nameBuffer = ""

    /// Preferisce la traccia (`trkpt`); in mancanza, la rotta (`rtept`); infine i waypoint
    var bestPoints: [CLLocationCoordinate2D] {
        if trkpts.count >= 2 { return trkpts }
        if rtepts.count >= 2 { return rtepts }
        return wpts
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "trkpt": if let c = coordinate(attributeDict) { trkpts.append(c) }
        case "rtept": if let c = coordinate(attributeDict) { rtepts.append(c) }
        case "wpt":   if let c = coordinate(attributeDict) { wpts.append(c) }
        case "name":
            // Prende il primo <name> del file (quello della traccia/metadata)
            if trackName == nil { capturingName = true; nameBuffer = "" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingName { nameBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "name", capturingName {
            capturingName = false
            trackName = nameBuffer
        }
    }

    private func coordinate(_ a: [String: String]) -> CLLocationCoordinate2D? {
        guard let latS = a["lat"], let lonS = a["lon"],
              let lat = Double(latS), let lon = Double(lonS),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
