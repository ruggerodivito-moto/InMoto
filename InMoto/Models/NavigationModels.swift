import Foundation
import CoreLocation

// MARK: - TurnDirection

enum TurnDirection {
    case straight, slightLeft, left, sharpLeft
    case slightRight, right, sharpRight
    case uTurn, roundabout, arrive, depart

    /// SF Symbol corrispondente alla manovra
    var sfSymbol: String {
        switch self {
        case .straight:     return "arrow.up"
        case .slightLeft:   return "arrow.up.left"
        case .left:         return "arrow.turn.up.left"
        case .sharpLeft:    return "arrow.turn.up.left"
        case .slightRight:  return "arrow.up.right"
        case .right:        return "arrow.turn.up.right"
        case .sharpRight:   return "arrow.turn.up.right"
        case .uTurn:        return "arrow.uturn.left"
        case .roundabout:   return "arrow.triangle.2.circlepath"
        case .arrive:       return "mappin.circle.fill"
        case .depart:       return "figure.walk"
        }
    }

    /// Parsa istruzioni in italiano o inglese prodotte da MKDirections
    static func parse(_ instruction: String) -> TurnDirection {
        let t = instruction.lowercased()
        if t.contains("arriv") || t.contains("destinazione") || t.contains("destination") { return .arrive }
        if t.contains("torna indietro") || t.contains("inversione") || t.contains("u-turn") { return .uTurn }
        if t.contains("rotonda") || t.contains("roundabout") { return .roundabout }
        if (t.contains("legger") || t.contains("slight")) && (t.contains("sinistra") || t.contains("left"))  { return .slightLeft }
        if (t.contains("legger") || t.contains("slight")) && (t.contains("destra")   || t.contains("right")) { return .slightRight }
        if t.contains("sinistra") || t.contains("left")  { return .left }
        if t.contains("destra")   || t.contains("right") { return .right }
        if t.contains("parte") || t.contains("depart")  { return .depart }
        return .straight
    }
}

struct GeocodedWaypoint: Codable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, latitude: Double, longitude: Double) {
        self.id = UUID().uuidString
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct RouteStep: Codable, Identifiable {
    let id: String
    let instruction: String
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(instruction: String, distanceMeters: Double, coordinate: CLLocationCoordinate2D) {
        self.id = UUID().uuidString
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct RouteLeg: Codable, Identifiable {
    let id: String
    let fromName: String
    let toName: String
    let distanceMeters: Double
    let durationSeconds: Double
    let polylinePoints: [[Double]]   // [[lat, lon], …]
    let steps: [RouteStep]

    var polylineCoordinates: [CLLocationCoordinate2D] {
        polylinePoints.compactMap { p in
            guard p.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
        }
    }

    init(fromName: String, toName: String, distanceMeters: Double, durationSeconds: Double,
         polylineCoordinates: [CLLocationCoordinate2D], steps: [RouteStep]) {
        self.id = UUID().uuidString
        self.fromName = fromName
        self.toName = toName
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.polylinePoints = polylineCoordinates.map { [$0.latitude, $0.longitude] }
        self.steps = steps
    }
}

struct NavigationRoute: Codable {
    let routeId: String
    let routeName: String
    let waypoints: [GeocodedWaypoint]
    let legs: [RouteLeg]

    var totalDistanceMeters: Double { legs.reduce(0) { $0 + $1.distanceMeters } }
    var totalDurationSeconds: Double { legs.reduce(0) { $0 + $1.durationSeconds } }

    var formattedDistance: String {
        String(format: "%.0f km", totalDistanceMeters / 1000)
    }

    var formattedDuration: String {
        let total = Int(totalDurationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)min"
    }
}
