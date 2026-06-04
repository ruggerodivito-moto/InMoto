import Foundation
import MapKit
import CoreLocation

class RouterService {
    static let shared = RouterService()
    private init() {}

    enum RouterError: LocalizedError {
        case noWaypoints
        case geocodingFailed(String)
        case routingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWaypoints:            return "Nessuna tappa definita nel percorso"
            case .geocodingFailed(let n): return "Impossibile localizzare: \(n)"
            case .routingFailed(let n):   return "Percorso non disponibile: \(n)"
            }
        }
    }

    // MARK: - Utility pubblica

    /// Reverse geocoding: coordinate → indirizzo testuale (es. "Genova, Liguria")
    static func reverseGeocode(_ location: CLLocation) async -> String {
        await withCheckedContinuation { cont in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                if let p = placemarks?.first {
                    let parts = [p.locality, p.administrativeArea].compactMap { $0 }
                    cont.resume(returning: parts.joined(separator: ", "))
                } else {
                    cont.resume(returning: "\(location.coordinate.latitude),\(location.coordinate.longitude)")
                }
            }
        }
    }

    // MARK: - Public

    func geocodeWaypoints(_ names: [String]) async throws -> [GeocodedWaypoint] {
        guard !names.isEmpty else { throw RouterError.noWaypoints }
        var result: [GeocodedWaypoint] = []
        for name in names {
            let wp = try await geocodeOne(name)
            result.append(wp)
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        return result
    }

    /// Come geocodeWaypoints ma gestisce anche stringhe coordinate "lat,lon"
    func geocodeWaypointsMixed(_ inputs: [String]) async throws -> [GeocodedWaypoint] {
        guard !inputs.isEmpty else { throw RouterError.noWaypoints }
        var result: [GeocodedWaypoint] = []
        for input in inputs {
            let wp = try await geocodeMixed(input)
            result.append(wp)
            if result.count < inputs.count {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        return result
    }

    func computeLegs(for waypoints: [GeocodedWaypoint]) async throws -> [RouteLeg] {
        var legs: [RouteLeg] = []
        for i in 0..<(waypoints.count - 1) {
            let leg = try await computeLeg(from: waypoints[i], to: waypoints[i + 1])
            legs.append(leg)
        }
        return legs
    }

    func cacheRoute(_ route: NavigationRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        try? data.write(to: cacheURL(for: route.routeId), options: .atomic)
    }

    func cachedRoute(for routeId: String) -> NavigationRoute? {
        guard let data = try? Data(contentsOf: cacheURL(for: routeId)) else { return nil }
        return try? JSONDecoder().decode(NavigationRoute.self, from: data)
    }

    func deleteCachedRoute(for routeId: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: routeId))
    }

    // MARK: - Private

    private func geocodeMixed(_ input: String) async throws -> GeocodedWaypoint {
        let t = input.trimmingCharacters(in: .whitespaces)
        // Gestisci formato "lat,lon" (da link Google Maps)
        let parts = t.components(separatedBy: ",")
        if parts.count == 2,
           let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
           let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)),
           abs(lat) <= 90, abs(lon) <= 180 {
            return GeocodedWaypoint(name: t, latitude: lat, longitude: lon)
        }
        return try await geocodeOne(t)
    }

    private func geocodeOne(_ address: String) async throws -> GeocodedWaypoint {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(address) { placemarks, _ in
                guard let location = placemarks?.first?.location else {
                    continuation.resume(throwing: RouterError.geocodingFailed(address))
                    return
                }
                continuation.resume(returning: GeocodedWaypoint(
                    name: address,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ))
            }
        }
    }

    private func computeLeg(from: GeocodedWaypoint, to: GeocodedWaypoint) async throws -> RouteLeg {
        return try await withCheckedThrowingContinuation { continuation in
            let request = MKDirections.Request()
            request.source      = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
            request.transportType = .automobile

            MKDirections(request: request).calculate { response, _ in
                guard let route = response?.routes.first else {
                    continuation.resume(throwing: RouterError.routingFailed("\(from.name) → \(to.name)"))
                    return
                }

                var coords = [CLLocationCoordinate2D](
                    repeating: .init(), count: route.polyline.pointCount)
                route.polyline.getCoordinates(
                    &coords, range: NSRange(location: 0, length: route.polyline.pointCount))

                let steps: [RouteStep] = route.steps.compactMap { step in
                    guard !step.instructions.isEmpty else { return nil }
                    var sc = [CLLocationCoordinate2D](
                        repeating: .init(), count: step.polyline.pointCount)
                    step.polyline.getCoordinates(
                        &sc, range: NSRange(location: 0, length: step.polyline.pointCount))
                    return RouteStep(
                        instruction: step.instructions,
                        distanceMeters: step.distance,
                        coordinate: sc.first ?? from.coordinate
                    )
                }

                continuation.resume(returning: RouteLeg(
                    fromName: from.name,
                    toName: to.name,
                    distanceMeters: route.distance,
                    durationSeconds: route.expectedTravelTime,
                    polylineCoordinates: coords,
                    steps: steps
                ))
            }
        }
    }

    private func cacheURL(for routeId: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nav_\(routeId).json")
    }
}
