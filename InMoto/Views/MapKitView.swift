import SwiftUI
import MapKit
import CoreLocation

struct MapKitView: UIViewRepresentable {
    let navRoute: NavigationRoute
    let currentLegIndex: Int
    let userLocation: CLLocation?
    let userHeading: Double?          // gradi da CLHeading.trueHeading; nil se non disponibile
    @Binding var isFollowingUser: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate        = context.coordinator
        map.showsUserLocation = true
        map.showsCompass    = true
        map.showsScale      = true
        map.isPitchEnabled  = true
        map.isRotateEnabled = true
        map.pointOfInterestFilter = .excludingAll

        // Rileva interazione manuale dell'utente (pan, pinch, rotation)
        for gestureType in [UIPanGestureRecognizer.self,
                            UIPinchGestureRecognizer.self,
                            UIRotationGestureRecognizer.self] as [UIGestureRecognizer.Type] {
            let g = gestureType.init(
                target: context.coordinator,
                action: #selector(Coordinator.userDidInteract))
            g.delegate = context.coordinator
            map.addGestureRecognizer(g)
        }

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Ricalcola overlays e pin solo al cambio di tratta (non ad ogni GPS tick)
        if context.coordinator.lastLegIndex != currentLegIndex {
            context.coordinator.lastLegIndex = currentLegIndex
            refreshOverlays(map)
            refreshAnnotations(map)
        }

        // Vista in primo piano: camera 3D che segue posizione e orientamento
        guard isFollowingUser, let loc = userLocation else { return }
        let bearing = resolvedHeading(location: loc, map: map)
        let camera = MKMapCamera()
        camera.centerCoordinate = loc.coordinate
        camera.altitude  = 500      // altezza occhio dal suolo in metri
        camera.pitch     = 45       // inclinazione 3D (0 = pianta, 90 = orizzonte)
        camera.heading   = bearing
        map.setCamera(camera, animated: false)
    }

    // MARK: - Overlays

    private func refreshOverlays(_ map: MKMapView) {
        map.removeOverlays(map.overlays)
        for (i, leg) in navRoute.legs.enumerated() {
            let coords = leg.polylineCoordinates
            guard !coords.isEmpty else { continue }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            line.title = i == currentLegIndex ? "current" : "other"
            map.addOverlay(line, level: .aboveRoads)
        }
    }

    // MARK: - Annotations

    private func refreshAnnotations(_ map: MKMapView) {
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        for (i, wp) in navRoute.waypoints.enumerated() {
            map.addAnnotation(WaypointAnnotation(
                coordinate: wp.coordinate,
                title: shortName(wp.name),
                index: i,
                isCompleted: i < currentLegIndex,
                isCurrent: i == currentLegIndex
            ))
        }
    }

    // MARK: - Helpers

    private func resolvedHeading(location: CLLocation, map: MKMapView) -> Double {
        if let h = userHeading, h >= 0 { return h }
        if location.course >= 0        { return location.course }
        return map.camera.heading       // mantiene l'ultimo heading noto
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapKitView
        var lastLegIndex: Int = -1      // forza il primo refresh

        init(_ parent: MapKitView) { self.parent = parent }

        // Quando l'utente muove la mappa manualmente, disattiva il seguimi
        @objc func userDidInteract(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began, parent.isFollowingUser else { return }
            DispatchQueue.main.async { self.parent.isFollowingUser = false }
        }

        // Riconosci i nostri gesture in contemporanea con quelli nativi della mappa
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: MKMapViewDelegate

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            if line.title == "current" {
                r.strokeColor = UIColor.systemOrange
                r.lineWidth   = 6
            } else {
                r.strokeColor = UIColor.systemGray3
                r.lineWidth   = 4
                r.lineDashPattern = [8, 4]
            }
            return r
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let wp = annotation as? WaypointAnnotation else { return nil }
            let view = map.dequeueReusableAnnotationView(withIdentifier: "wp")
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "wp")
            view.annotation = annotation
            view.image = wpImage(for: wp)
            view.canShowCallout = true
            return view
        }

        private func wpImage(for wp: WaypointAnnotation) -> UIImage {
            let size: CGFloat = 32
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let color: UIColor = wp.isCompleted ? .systemGreen
                                   : wp.isCurrent  ? .systemOrange
                                   : .systemIndigo
                color.setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size-4, height: size-4)).fill()
                let label = "\(wp.index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.white
                ]
                let sz = label.size(withAttributes: attrs)
                label.draw(at: CGPoint(x: (size-sz.width)/2, y: (size-sz.height)/2),
                           withAttributes: attrs)
            }
        }
    }
}

// MARK: - WaypointAnnotation

class WaypointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let index: Int
    let isCompleted: Bool
    let isCurrent: Bool

    init(coordinate: CLLocationCoordinate2D, title: String, index: Int,
         isCompleted: Bool, isCurrent: Bool) {
        self.coordinate  = coordinate
        self.title       = title
        self.index       = index
        self.isCompleted = isCompleted
        self.isCurrent   = isCurrent
    }
}
