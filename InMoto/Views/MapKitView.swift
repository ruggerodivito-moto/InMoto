import SwiftUI
import MapKit
import CoreLocation

struct MapKitView: UIViewRepresentable {
    let navRoute: NavigationRoute
    let currentLegIndex: Int
    let currentStepIndex: Int
    let userLocation: CLLocation?
    let userHeading: Double?
    @Binding var isFollowingUser: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate            = context.coordinator
        map.showsUserLocation   = false   // usiamo la nostra icona moto
        map.showsCompass        = true
        map.showsScale          = true
        map.isPitchEnabled      = true
        map.isRotateEnabled     = true
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
        // Overlay e pin tappe: aggiorna solo al cambio tratta/step
        let key = currentLegIndex * 1000 + currentStepIndex
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            refreshOverlays(map)
            refreshTurnAnnotations(map, context: context)
            if !isFollowingUser { fitRoute(map) }
        }

        // Aggiorna/crea icona moto sulla mappa
        if let loc = userLocation {
            updateMotoAnnotation(map, context: context, location: loc)
        }

        // Camera 3D centrata sull'icona moto
        guard isFollowingUser, let loc = userLocation else { return }
        let bearing = resolvedHeading(location: loc, map: map)
        let camera = MKMapCamera()
        camera.centerCoordinate = loc.coordinate
        camera.altitude = 500
        camera.pitch    = 45
        camera.heading  = bearing
        map.setCamera(camera, animated: false)
    }

    // MARK: - Overlay percorso

    private func refreshOverlays(_ map: MKMapView) {
        map.removeOverlays(map.overlays)
        for (i, leg) in navRoute.legs.enumerated() {
            let coords = leg.polylineCoordinates
            guard !coords.isEmpty else { continue }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            line.title = i < currentLegIndex  ? "done"
                       : i == currentLegIndex ? "current"
                       : "future"
            map.addOverlay(line, level: .aboveRoads)
        }
    }

    // MARK: - Annotazioni svolte

    private func refreshTurnAnnotations(_ map: MKMapView, context: Context) {
        // Rimuovi solo TurnAnnotation e WaypointAnnotation, NON la moto
        let toRemove = map.annotations.filter {
            $0 is TurnAnnotation || $0 is WaypointAnnotation
        }
        map.removeAnnotations(toRemove)

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

        // Marcatori prossime svolte (max 3 step avanti)
        guard currentLegIndex < navRoute.legs.count else { return }
        let steps = navRoute.legs[currentLegIndex].steps
        guard !steps.isEmpty else { return }
        let start = min(currentStepIndex, steps.count - 1)
        for i in start..<min(start + 3, steps.count) {
            let step = steps[i]
            guard !step.instruction.isEmpty else { continue }
            let dir = TurnDirection.parse(step.instruction)
            if i == start || dir != .straight {
                map.addAnnotation(TurnAnnotation(
                    coordinate: step.coordinate,
                    direction: dir,
                    instruction: step.instruction,
                    isNext: i == start
                ))
            }
        }
    }

    // MARK: - Icona moto (posizione utente)

    private func updateMotoAnnotation(_ map: MKMapView,
                                      context: Context,
                                      location: CLLocation) {
        if let ann = context.coordinator.motoAnnotation {
            // Aggiorna coordinate → MapKit la sposta automaticamente (KVO)
            ann.coordinate = location.coordinate
        } else {
            let ann = MotoAnnotation(coordinate: location.coordinate)
            map.addAnnotation(ann)
            context.coordinator.motoAnnotation = ann
        }
    }

    // MARK: - Fit overview

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
        var motoAnnotation: MotoAnnotation?

        init(_ parent: MapKitView) { self.parent = parent }

        @objc func userDidInteract(_ g: UIGestureRecognizer) {
            guard g.state == .began, parent.isFollowingUser else { return }
            DispatchQueue.main.async { self.parent.isFollowingUser = false }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        // MARK: Renderer overlay

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            switch line.title {
            case "current":
                r.strokeColor = UIColor.systemBlue    // BLU come Google Maps
                r.lineWidth   = 8
                r.lineCap     = .round
                r.lineJoin    = .round
            case "done":
                r.strokeColor = UIColor.systemGray4
                r.lineWidth   = 5
            default:
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.35)
                r.lineWidth   = 5
                r.lineDashPattern = [8, 5]
            }
            return r
        }

        // MARK: Annotation view

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MotoAnnotation:
                return motoView(map, annotation: annotation)
            case let turn as TurnAnnotation:
                return turnView(map, turn: turn)
            case let wp as WaypointAnnotation:
                return waypointView(map, wp: wp)
            default:
                return nil
            }
        }

        // Icona moto — sempre puntata verso l'alto (la mappa ruota sotto di lei)
        private func motoView(_ map: MKMapView, annotation: MKAnnotation) -> MKAnnotationView {
            let id = "moto"
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation    = annotation
            view.image         = motoImage()
            view.canShowCallout = false
            view.layer.zPosition = 1000   // sempre sopra gli altri pin
            return view
        }

        private func motoImage() -> UIImage {
            let size: CGFloat = 52
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let c = ctx.cgContext

                // Alone bianco
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()

                // Cerchio arancione
                UIColor.systemOrange.setFill()
                UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: size-6, height: size-6)).fill()

                // Icona moto ruotata di -90° per puntare verso l'alto
                // (SF Symbol "motorcycle" guarda a destra per default)
                let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
                let name = UIImage(systemName: "motorcycle") != nil ? "motorcycle" : "car.fill"
                if let icon = UIImage(systemName: name, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    c.saveGState()
                    c.translateBy(x: size/2, y: size/2)
                    c.rotate(by: -.pi / 2)   // ruota per puntare in su
                    icon.draw(at: CGPoint(x: -icon.size.width/2, y: -icon.size.height/2))
                    c.restoreGState()
                }
            }
        }

        // Marcatore svolta
        private func turnView(_ map: MKMapView, turn: TurnAnnotation) -> MKAnnotationView {
            let id = "turn"
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: turn, reuseIdentifier: id)
            view.annotation     = turn
            view.canShowCallout = true
            view.image          = turnImage(for: turn)
            view.centerOffset   = CGPoint(x: 0, y: -20)
            return view
        }

        private func turnImage(for turn: TurnAnnotation) -> UIImage {
            let size: CGFloat = turn.isNext ? 44 : 32
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let bg: UIColor = turn.isNext ? .systemOrange : .systemOrange.withAlphaComponent(0.6)
                bg.setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size-4, height: size-4)).fill()
                UIColor.white.setStroke()
                let b = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size-4, height: size-4))
                b.lineWidth = turn.isNext ? 2.5 : 1.5
                b.stroke()
                let config = UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .bold)
                if let icon = UIImage(systemName: turn.direction.sfSymbol, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(
                        x: (size - icon.size.width)  / 2,
                        y: (size - icon.size.height) / 2))
                }
            }
        }

        // Pin tappa
        private func waypointView(_ map: MKMapView, wp: WaypointAnnotation) -> MKAnnotationView {
            let id = "wp"
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: wp, reuseIdentifier: id)
            view.annotation    = wp
            view.canShowCallout = true
            view.image         = waypointImage(for: wp)
            return view
        }

        private func waypointImage(for wp: WaypointAnnotation) -> UIImage {
            let size: CGFloat = 32
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let color: UIColor = wp.isCompleted ? .systemGreen
                                   : wp.isCurrent  ? .systemOrange
                                   : .systemBlue
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

// MARK: - Annotation classes

/// Posizione utente — usa KVO per aggiornare automaticamente la mappa
class MotoAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

class WaypointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let index: Int
    let isCompleted: Bool
    let isCurrent: Bool
    init(coordinate: CLLocationCoordinate2D, title: String, index: Int,
         isCompleted: Bool, isCurrent: Bool) {
        self.coordinate = coordinate; self.title = title; self.index = index
        self.isCompleted = isCompleted; self.isCurrent = isCurrent
    }
}

class TurnAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let direction: TurnDirection
    let title: String?
    let isNext: Bool
    init(coordinate: CLLocationCoordinate2D, direction: TurnDirection,
         instruction: String, isNext: Bool) {
        self.coordinate = coordinate; self.direction = direction
        self.title = instruction; self.isNext = isNext
    }
}
