import SwiftUI
import MapKit

// Wrapper UIViewRepresentable per MKMapView.
// Disegna tutte le polyline delle tratte e i pin delle tappe.
// La tratta corrente è arancione, le altre grigie.
struct MapKitView: UIViewRepresentable {
    let navRoute: NavigationRoute
    let currentLegIndex: Int
    let userLocation: CLLocation?
    var onMapReady: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .followWithHeading
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        // Disegna polyline per ogni tratta
        for (i, leg) in navRoute.legs.enumerated() {
            let coords = leg.polylineCoordinates
            guard !coords.isEmpty else { continue }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            polyline.title = i == currentLegIndex ? "current" : "other"
            map.addOverlay(polyline, level: .aboveRoads)
        }

        // Pin tappe (waypoints)
        for (i, wp) in navRoute.waypoints.enumerated() {
            let ann = WaypointAnnotation(
                coordinate: wp.coordinate,
                title: shortName(wp.name),
                index: i,
                isCompleted: i < currentLegIndex,
                isCurrent: i == currentLegIndex
            )
            map.addAnnotation(ann)
        }

        // Centra sulla tratta corrente al cambio di tratta
        if currentLegIndex < navRoute.legs.count {
            let leg = navRoute.legs[currentLegIndex]
            let pts = leg.polylineCoordinates
            if !pts.isEmpty {
                let polyline = MKPolyline(coordinates: pts, count: pts.count)
                let rect = polyline.boundingMapRect
                map.setVisibleMapRect(
                    rect.insetBy(dx: -rect.size.width * 0.3, dy: -rect.size.height * 0.3),
                    animated: true
                )
            }
        }
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitView

        init(_ parent: MapKitView) {
            self.parent = parent
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            parent.onMapReady?()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            if polyline.title == "current" {
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 6
            } else {
                renderer.strokeColor = UIColor.systemGray3
                renderer.lineWidth = 4
                renderer.lineDashPattern = [8, 4]
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let wp = annotation as? WaypointAnnotation else { return nil }
            let id = "waypoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            let size: CGFloat = 32
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let img = renderer.image { ctx in
                let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
                let color: UIColor = wp.isCompleted ? .systemGreen
                                   : wp.isCurrent  ? .systemOrange
                                   : .systemIndigo
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()
                UIColor.white.setFill()
                let label = "\(wp.index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.white
                ]
                let sz = label.size(withAttributes: attrs)
                label.draw(at: CGPoint(
                    x: (size - sz.width) / 2,
                    y: (size - sz.height) / 2
                ), withAttributes: attrs)
            }
            view.image = img
            view.centerOffset = .zero
            view.canShowCallout = true
            return view
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
        self.coordinate = coordinate
        self.title = title
        self.index = index
        self.isCompleted = isCompleted
        self.isCurrent = isCurrent
    }
}
