import SwiftUI
import MapKit
import CoreLocation

struct MapKitView: UIViewRepresentable {
    let navRoute: NavigationRoute
    let currentLegIndex: Int
    let currentStepIndex: Int           // step corrente nella tratta
    let userLocation: CLLocation?
    let userHeading: Double?
    @Binding var isFollowingUser: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate          = context.coordinator
        map.showsUserLocation = true
        map.showsCompass      = true
        map.showsScale        = true
        map.isPitchEnabled    = true
        map.isRotateEnabled   = true
        map.pointOfInterestFilter = .excludingAll

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
        let key = currentLegIndex * 1000 + currentStepIndex
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            refreshOverlays(map)
            refreshAnnotations(map)
            // In overview: adatta la vista al percorso completo
            if !isFollowingUser { fitRoute(map) }
        }

        guard isFollowingUser, let loc = userLocation else { return }
        let bearing = resolvedHeading(location: loc, map: map)
        let camera = MKMapCamera()
        camera.centerCoordinate = loc.coordinate
        camera.altitude = 500
        camera.pitch    = 45
        camera.heading  = bearing
        map.setCamera(camera, animated: false)
    }

    /// Zooma la mappa per mostrare l'intero percorso (modalità anteprima)
    private func fitRoute(_ map: MKMapView) {
        var rect = MKMapRect.null
        for overlay in map.overlays { rect = rect.union(overlay.boundingMapRect) }
        guard !rect.isNull else { return }
        let padded = rect.insetBy(dx: -rect.size.width * 0.12, dy: -rect.size.height * 0.12)
        map.setVisibleMapRect(
            padded,
            edgePadding: UIEdgeInsets(top: 80, left: 20, bottom: 160, right: 20),
            animated: true
        )
    }

    // MARK: - Overlays

    private func refreshOverlays(_ map: MKMapView) {
        map.removeOverlays(map.overlays)

        for (i, leg) in navRoute.legs.enumerated() {
            let coords = leg.polylineCoordinates
            guard !coords.isEmpty else { continue }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            if i < currentLegIndex {
                line.title = "done"
            } else if i == currentLegIndex {
                line.title = "current"
            } else {
                line.title = "future"
            }
            map.addOverlay(line, level: .aboveRoads)
        }
    }

    // MARK: - Annotations

    private func refreshAnnotations(_ map: MKMapView) {
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        // Pin tappe principali
        for (i, wp) in navRoute.waypoints.enumerated() {
            map.addAnnotation(WaypointAnnotation(
                coordinate: wp.coordinate,
                title: shortName(wp.name),
                index: i,
                isCompleted: i < currentLegIndex,
                isCurrent: i == currentLegIndex
            ))
        }

        // Marcatori di svolta: prossimi 3 step della tratta corrente
        guard currentLegIndex < navRoute.legs.count else { return }
        let leg = navRoute.legs[currentLegIndex]
        let steps = leg.steps
        guard !steps.isEmpty else { return }

        let startStep = min(currentStepIndex, steps.count - 1)
        let endStep   = min(startStep + 3, steps.count)

        for i in startStep..<endStep {
            let step = steps[i]
            // Salta step "arrivato" se non sono sull'ultimo
            guard !step.instruction.isEmpty else { continue }
            let direction = TurnDirection.parse(step.instruction)
            // Non mettere un pin "dritto" per ogni step — solo le svolte vere
            if i == startStep || direction != .straight {
                map.addAnnotation(TurnAnnotation(
                    coordinate: step.coordinate,
                    direction: direction,
                    instruction: step.instruction,
                    isNext: i == startStep
                ))
            }
        }
    }

    // MARK: - Helpers

    private func resolvedHeading(location: CLLocation, map: MKMapView) -> Double {
        if let h = userHeading, h >= 0 { return h }
        if location.course >= 0        { return location.course }
        return map.camera.heading
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapKitView
        var lastKey: Int = -1

        init(_ parent: MapKitView) { self.parent = parent }

        @objc func userDidInteract(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began, parent.isFollowingUser else { return }
            DispatchQueue.main.async { self.parent.isFollowingUser = false }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Renderer overlay

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            switch line.title {
            case "current":
                r.strokeColor = UIColor.systemOrange
                r.lineWidth   = 8
                r.lineCap     = .round
                r.lineJoin    = .round
            case "done":
                r.strokeColor = UIColor.systemGray4
                r.lineWidth   = 5
            default: // future
                r.strokeColor = UIColor.systemGray3
                r.lineWidth   = 4
                r.lineDashPattern = [8, 5]
            }
            return r
        }

        // MARK: Annotation view

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let turn as TurnAnnotation:
                return turnView(map, turn: turn)
            case let wp as WaypointAnnotation:
                return waypointView(map, wp: wp)
            default:
                return nil
            }
        }

        // Vista marcatore di svolta
        private func turnView(_ map: MKMapView, turn: TurnAnnotation) -> MKAnnotationView {
            let id = "turn"
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: turn, reuseIdentifier: id)
            view.annotation      = turn
            view.canShowCallout  = true
            view.image           = turnImage(for: turn)
            view.centerOffset    = CGPoint(x: 0, y: -20)
            return view
        }

        private func turnImage(for turn: TurnAnnotation) -> UIImage {
            let size: CGFloat = turn.isNext ? 44 : 32
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                // Sfondo circolare
                let bgColor: UIColor = turn.isNext ? .systemOrange : .systemOrange.withAlphaComponent(0.6)
                bgColor.setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size-4, height: size-4)).fill()
                // Bordo bianco
                UIColor.white.setStroke()
                let border = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size-4, height: size-4))
                border.lineWidth = turn.isNext ? 2.5 : 1.5
                border.stroke()
                // Icona SF Symbol
                let config = UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .bold)
                if let icon = UIImage(systemName: turn.direction.sfSymbol, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(
                        x: (size - icon.size.width)  / 2,
                        y: (size - icon.size.height) / 2
                    ))
                }
            }
        }

        // Vista pin tappa
        private func waypointView(_ map: MKMapView, wp: WaypointAnnotation) -> MKAnnotationView {
            let id = "wp"
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: wp, reuseIdentifier: id)
            view.annotation     = wp
            view.canShowCallout = true
            view.image          = waypointImage(for: wp)
            return view
        }

        private func waypointImage(for wp: WaypointAnnotation) -> UIImage {
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

// MARK: - Annotations

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

class TurnAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let direction: TurnDirection
    let title: String?
    let isNext: Bool   // true = prossima svolta immediata (più grande)

    init(coordinate: CLLocationCoordinate2D, direction: TurnDirection,
         instruction: String, isNext: Bool) {
        self.coordinate = coordinate
        self.direction  = direction
        self.title      = instruction
        self.isNext     = isNext
    }
}
