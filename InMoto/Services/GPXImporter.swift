import Foundation
import CoreLocation

/// Importa una traccia GPX (Garmin, Strava, Komoot…) e la trasforma in un
/// percorso navigabile che segue **esattamente** il tracciato registrato: i
/// punti della traccia diventano la polyline di navigazione, senza alcun
/// ricalcolo stradale (niente geocoding, niente MKDirections).
///
/// Se il file contiene **waypoint nominati** (`<wpt>` con nome/descrizione, es.
/// soste o punti d'interesse di un percorso pianificato), questi diventano i
/// nodi del percorso (con il loro nome e nota); altrimenti la traccia viene
/// spezzata in nodi sintetici per dare avanzamento ed ETA.
struct GPXImporter {

    /// Punto nominato del GPX (`<wpt>`): nome + eventuale nota/descrizione.
    struct NamedPoint {
        let name: String
        let note: String?
        let coordinate: CLLocationCoordinate2D
    }

    struct ParsedTrack {
        let name: String
        let points: [CLLocationCoordinate2D]
        let waypoints: [NamedPoint]
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
        return ParsedTrack(name: name, points: pts, waypoints: delegate.namedPoints)
    }

    // MARK: - Costruzione percorso navigabile

    /// Confine di tratta: indice sul tracciato + etichetta + eventuale nota.
    private struct Boundary { let idx: Int; let name: String; let note: String? }

    static func buildRoute(from track: ParsedTrack, displayName: String,
                           transport: TransportMode) -> (route: MotoRoute, navRoute: NavigationRoute) {
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

        // Nodi: dai waypoint nominati se presenti, altrimenti sintetici
        var boundaries = track.waypoints.isEmpty
            ? syntheticBoundaries(pts: pts, cum: cum, total: total, totalKm: totalKm, endName: name)
            : namedBoundaries(pts: pts, named: track.waypoints, endName: name)

        // Salvaguardia anelli: con soli 2 nodi e partenza ≈ arrivo, una singola
        // tratta farebbe scattare il falso "arrivo". Inserisci un nodo a metà.
        if boundaries.count == 2,
           RouteGeometry.distance(pts[boundaries[0].idx], pts[boundaries[1].idx]) < 100 {
            let midIdx = cum.firstIndex { $0 >= total / 2 } ?? (pts.count / 2)
            if midIdx > 1 && midIdx < pts.count - 1 {
                boundaries.insert(Boundary(idx: midIdx, name: "Metà percorso", note: nil), at: 1)
            }
        }

        // Waypoint (uno per confine) con nome e nota
        let waypoints: [GeocodedWaypoint] = boundaries.map {
            GeocodedWaypoint(name: $0.name,
                             latitude: pts[$0.idx].latitude,
                             longitude: pts[$0.idx].longitude,
                             note: $0.note)
        }

        // Tratte: sotto-polyline tra confini consecutivi (estremo condiviso, che
        // RouteGeometry deduplica come fa per le tratte di MKDirections)
        let avgSpeedKmh = transport.avgSpeedKmh   // tempi tarati sul mezzo (la traccia non ha tempi)
        var legs: [RouteLeg] = []
        for i in 0..<(boundaries.count - 1) {
            let a = boundaries[i].idx, b = boundaries[i + 1].idx
            let slice = Array(pts[a...b])
            let legMeters = cum[b] - cum[a]
            let legSeconds = legMeters / 1000 / avgSpeedKmh * 3600
            legs.append(RouteLeg(fromName: boundaries[i].name,
                                 toName: boundaries[i + 1].name,
                                 distanceMeters: legMeters,
                                 durationSeconds: legSeconds,
                                 polylineCoordinates: slice,
                                 steps: synthesizeSteps(points: slice)))
        }

        let routeId = UUID().uuidString
        let navRoute = NavigationRoute(routeId: routeId, routeName: name,
                                       waypoints: waypoints, legs: legs,
                                       transport: transport.rawValue)

        let nNodi = track.waypoints.count
        let descrizione = nNodi > 0
            ? "Traccia GPX (\(transport.label.lowercased())) · \(pts.count) punti · \(nNodi) nod\(nNodi == 1 ? "o" : "i") dal file · segue esattamente il tracciato."
            : "Traccia GPX (\(transport.label.lowercased())) · \(pts.count) punti · segue esattamente il tracciato registrato."

        let route = MotoRoute(
            id: routeId,
            nome: name,
            partenza: waypoints.first?.name ?? "Partenza",
            arrivo: waypoints.last?.name ?? name,
            regione: "",
            km: max(1, Int(totalKm.rounded())),
            durataMin: max(1, Int(total / 1000 / avgSpeedKmh * 60)),
            difficolta: "Media", stelle: 0,
            descrizione: descrizione,
            tappe: waypoints.map { $0.name },
            waypointsGmaps: waypoints.map { "\($0.latitude),\($0.longitude)" },
            tags: ["gpx", "personale"],
            fonte: "GPX importato", stagione: "Tutto l'anno", isCustom: true,
            legKm: legs.map { max(1, Int($0.distanceMeters / 1000)) },
            legMin: legs.map { max(1, Int($0.durationSeconds / 60)) },
            mezzo: transport.rawValue
        )
        return (route, navRoute)
    }

    // MARK: - Nodi

    /// Nodi dai waypoint nominati del GPX, agganciati al punto più vicino della
    /// traccia e ordinati per progressione. Partenza/arrivo della traccia sono
    /// sempre inclusi (prendono il nome del waypoint se ne coincide uno).
    private static func namedBoundaries(pts: [CLLocationCoordinate2D],
                                        named: [GPXImporter.NamedPoint],
                                        endName: String) -> [Boundary] {
        let n = pts.count
        let snap = max(2, n / 50)        // tolleranza (in indici) per "sta all'estremo"

        var startName = "Partenza", startNote: String? = nil
        var finalName = endName, finalNote: String? = nil
        var interior: [Boundary] = []

        for wp in named {
            let idx = nearestIndex(of: wp.coordinate, in: pts)
            if idx <= snap {
                startName = wp.name; startNote = wp.note
            } else if idx >= n - 1 - snap {
                finalName = wp.name; finalNote = wp.note
            } else {
                interior.append(Boundary(idx: idx, name: wp.name, note: wp.note))
            }
        }
        interior.sort { $0.idx < $1.idx }

        var result: [Boundary] = [Boundary(idx: 0, name: startName, note: startNote)]
        for b in interior where b.idx - result.last!.idx >= 2 {
            result.append(b)
        }
        // Arrivo: se l'ultimo interno è vicino alla fine usa il suo nome, altrimenti aggiungi
        if let last = result.last, n - 1 - last.idx < 2 {
            result[result.count - 1] = Boundary(idx: n - 1, name: last.name, note: last.note)
        } else {
            result.append(Boundary(idx: n - 1, name: finalName, note: finalNote))
        }
        return result
    }

    /// Nodi sintetici: spezza la traccia in tratte uguali (per ETA e per evitare
    /// il falso "arrivo" sugli anelli, dove partenza ≈ arrivo).
    private static func syntheticBoundaries(pts: [CLLocationCoordinate2D], cum: [Double],
                                            total: Double, totalKm: Double, endName: String) -> [Boundary] {
        let segCount = max(2, min(8, Int((totalKm / 4).rounded())))
        var idxs: [Int] = [0]
        for s in 1..<segCount {
            let target = total * Double(s) / Double(segCount)
            let idx = cum.firstIndex { $0 >= target } ?? (pts.count - 1)
            if idx > idxs.last! { idxs.append(idx) }
        }
        if idxs.last! != pts.count - 1 { idxs.append(pts.count - 1) }

        return idxs.enumerated().map { k, idx in
            if k == 0 { return Boundary(idx: idx, name: "Partenza", note: nil) }
            if k == idxs.count - 1 { return Boundary(idx: idx, name: endName, note: nil) }
            return Boundary(idx: idx, name: "km \(Int((cum[idx] / 1000).rounded()))", note: nil)
        }
    }

    private static func nearestIndex(of c: CLLocationCoordinate2D,
                                     in pts: [CLLocationCoordinate2D]) -> Int {
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, p) in pts.enumerated() {
            let d = RouteGeometry.distance(c, p)
            if d < bestD { bestD = d; best = i }
        }
        return best
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
    private(set) var namedPoints: [GPXImporter.NamedPoint] = []

    // Stato per il <wpt> in costruzione
    private var inWpt = false
    private var wptCoord: CLLocationCoordinate2D?
    private var wptName = ""
    private var wptDesc = ""
    private var wptCmt = ""

    // Campo di testo attualmente in cattura: "wname"/"wdesc"/"wcmt"/"trackname"
    private var capturing: String?
    private var buffer = ""

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
        case "wpt":
            inWpt = true
            wptCoord = coordinate(attributeDict)
            wptName = ""; wptDesc = ""; wptCmt = ""
            if let c = wptCoord { wpts.append(c) }
        case "name":
            if inWpt { capturing = "wname"; buffer = "" }
            else if trackName == nil { capturing = "trackname"; buffer = "" }
        case "desc": if inWpt { capturing = "wdesc"; buffer = "" }
        case "cmt":  if inWpt { capturing = "wcmt"; buffer = "" }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "name":
            if capturing == "wname" { wptName = buffer }
            else if capturing == "trackname" { trackName = buffer }
            capturing = nil
        case "desc": if capturing == "wdesc" { wptDesc = buffer }; capturing = nil
        case "cmt":  if capturing == "wcmt"  { wptCmt = buffer };  capturing = nil
        case "wpt":
            if let c = wptCoord {
                let nm = wptName.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = [wptDesc, wptCmt]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                namedPoints.append(GPXImporter.NamedPoint(
                    name: nm.isEmpty ? "Nodo \(namedPoints.count + 1)" : nm,
                    note: note,
                    coordinate: c))
            }
            inWpt = false
            wptCoord = nil
        default: break
        }
    }

    private func coordinate(_ a: [String: String]) -> CLLocationCoordinate2D? {
        guard let latS = a["lat"], let lonS = a["lon"],
              let lat = Double(latS), let lon = Double(lonS),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
