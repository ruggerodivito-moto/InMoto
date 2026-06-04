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

    // MARK: - Public

    func geocodeWaypoints(_ names: [String]) async throws -> [GeocodedWaypoint] {
        guard !names.isEmpty else { throw RouterError.noWaypoints }
        var result: [GeocodedWaypoint] = []
        for name in names {
            let wp = try await geocodeOne(name)
            result.append(wp)
            // Piccola pausa per rispettare i rate limit di CLGeocoder
            try? await Task.sleep(nanoseconds: 350_000_000)
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
