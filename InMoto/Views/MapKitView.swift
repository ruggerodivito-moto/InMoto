import SwiftUI
import MapKit
import CoreLocation

struct MapKitView: UIViewRepresentable {
    let navRoute: NavigationRoute
    let routeVersion: Int                  // incrementa dopo un ricalcolo percorso
    let routePoints: [CLLocationCoordinate2D]
    let matchedPointIndex: Int             // posizione agganciata sul percorso
    let currentLegIndex: Int
    let upcomingTurns: [NavigationSession.UpcomingTurn]
    let userLocation: CLLocation?
    let userHeading: Double?
    @Binding var isFollowingUser: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate              = context.coordinator
        map.showsUserLocation     = false
        map.showsCompass          = false   // disabilitiamo la bussola nativa (la mappa ruota)
        map.showsScale            = true
        map.isPitchEnabled        = true
        map.isRotateEnabled       = true
        map.pointOfInterestFilter = .excludingAll

        // Gesture per rilevare movimento manuale → disabilita seguimi
        [UIPanGestureRecognizer.self,
         UIPinchGestureRecognizer.self,
         UIRotationGestureRecognizer.self].forEach { type in
            let g = type.init(target: context.coordinator,
                              action: #selector(Coordinator.userPanned))
            g.delegate = context.coordinator
            map.addGestureRecognizer(g)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        // 1. Geometria del percorso: ricostruita solo dopo un ricalcolo
        if coord.lastVersion != routeVersion {
            coord.lastVersion    = routeVersion
            coord.lastSplitIndex = -1
            coord.lastLegIndex   = -1
            coord.lastTurnKey    = Int.min
            map.removeOverlays(map.overlays)
            if routePoints.count >= 2 {
                let border = MKPolyline(coordinates: routePoints, count: routePoints.count)
                border.title = "border"
                map.addOverlay(border, level: .aboveRoads)
            }
            if !isFollowingUser { showOverview(map) }
        }

        // 2. Percorso già fatto (grigio) / futuro (blu), spezzati sulla posizione
        if coord.lastSplitIndex != matchedPointIndex, routePoints.count >= 2 {
            coord.lastSplitIndex = matchedPointIndex
            let old = map.overlays.compactMap { $0 as? MKPolyline }
                .filter { $0.title == "done" || $0.title == "todo" }
            map.removeOverlays(old)

            let split = min(max(matchedPointIndex, 0), routePoints.count - 1)
            if split >= 1 {
                let done = MKPolyline(coordinates: Array(routePoints[0...split]), count: split + 1)
                done.title = "done"
                map.addOverlay(done, level: .aboveRoads)
            }
            if split <= routePoints.count - 2 {
                let todo = MKPolyline(coordinates: Array(routePoints[split...]),
                                      count: routePoints.count - split)
                todo.title = "todo"
                map.addOverlay(todo, level: .aboveRoads)
            }
        }

        // 3. Pin tappe (stato fatto/attiva/da fare)
        if coord.lastLegIndex != currentLegIndex {
            coord.lastLegIndex = currentLegIndex
            map.removeAnnotations(map.annotations.filter { $0 is WaypointPin })
            for (i, wp) in navRoute.waypoints.enumerated() {
                map.addAnnotation(WaypointPin(
                    coordinate: wp.coordinate,
                    label: "\(i + 1)",
                    state: i < currentLegIndex ? .done : i == currentLegIndex ? .active : .todo
                ))
            }
        }

        // 4. Marcatori prossime svolte
        let turnKey = upcomingTurns.first?.key ?? -1
        if coord.lastTurnKey != turnKey {
            coord.lastTurnKey = turnKey
            map.removeAnnotations(map.annotations.filter { $0 is TurnPin })
            for t in upcomingTurns {
                map.addAnnotation(TurnPin(
                    coordinate: t.coordinate,
                    direction: t.direction,
                    title: t.instruction,
                    isPrimary: t.isPrimary
                ))
            }
        }

        // 5. Icona moto: crea al primo fix GPS, poi anima verso la nuova posizione
        if let loc = userLocation {
            if let ann = coord.motoPin {
                UIView.animate(withDuration: 0.9, delay: 0,
                               options: [.curveLinear, .beginFromCurrentState]) {
                    ann.coordinate = loc.coordinate
                }
            } else {
                let ann = MotoPin(coordinate: loc.coordinate)
                map.addAnnotation(ann)
                coord.motoPin = ann
            }
        }

        // 6. Camera: segui l'utente solo in modalità navigazione attiva
        guard isFollowingUser, let loc = userLocation else { return }

        let speed = max(0, loc.speed)
        let heading: Double
        if loc.course >= 0, speed > 2 {
            heading = loc.course            // in movimento: direzione di marcia
        } else if let h = userHeading, h >= 0 {
            heading = h                     // fermo: bussola
        } else {
            heading = map.camera.heading
        }

        // Quota in funzione della velocità: più veloce → vista più ampia.
        // Lookahead in avanti solo in movimento: da fermo (es. all'avvio della
        // tappa) la moto resta centrata sulla posizione; in marcia il centro
        // scivola avanti per mostrare il percorso futuro, come Google Maps.
        let altitude = min(1500.0, 600.0 + speed * 40.0)
        let lookahead = speed > 1 ? min(altitude * 0.28, speed * 16.0) : 0
        let center = lookahead > 0
            ? Self.offset(loc.coordinate, byMeters: lookahead, bearing: heading)
            : loc.coordinate
        let cam = MKMapCamera(lookingAtCenter: center, fromDistance: altitude,
                              pitch: 45, heading: heading)
        // Interpolazione lineare tra un fix GPS e l'altro → movimento fluido
        UIView.animate(withDuration: 0.9, delay: 0,
                       options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            map.camera = cam
        }
    }

    // MARK: - Overview

    private func showOverview(_ map: MKMapView) {
        var rect = MKMapRect.null
        map.overlays.forEach { rect = rect.union($0.boundingMapRect) }
        guard !rect.isNull else { return }
        let inset = rect.insetBy(dx: -rect.size.width  * 0.1,
                                 dy: -rect.size.height * 0.1)
        map.setVisibleMapRect(inset,
                              edgePadding: UIEdgeInsets(top: 80, left: 24, bottom: 160, right: 24),
                              animated: true)
    }

    /// Sposta una coordinata di `meters` metri nella direzione `bearing` (gradi)
    private static func offset(_ c: CLLocationCoordinate2D,
                               byMeters meters: Double,
                               bearing: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let br = bearing * .pi / 180
        let lat1 = c.latitude * .pi / 180
        let lon1 = c.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / R) + cos(lat1) * sin(meters / R) * cos(br))
        let lon2 = lon1 + atan2(sin(br) * sin(meters / R) * cos(lat1),
                                cos(meters / R) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapKitView
        var lastVersion    = -1
        var lastSplitIndex = -1
        var lastLegIndex   = -1
        var lastTurnKey    = Int.min
        var motoPin: MotoPin?

        init(_ parent: MapKitView) { self.parent = parent }

        @objc func userPanned(_ g: UIGestureRecognizer) {
            guard g.state == .began, parent.isFollowingUser else { return }
            DispatchQueue.main.async { self.parent.isFollowingUser = false }
        }

        func gestureRecognizer(_ a: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

        // MARK: Overlay renderer

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: poly)
            r.lineCap  = .round
            r.lineJoin = .round
            switch poly.title {
            case "border":
                r.strokeColor = UIColor.white.withAlphaComponent(0.9)
                r.lineWidth   = 13
            case "done":
                r.strokeColor = UIColor.systemGray3
                r.lineWidth   = 8
            default: // todo (percorso futuro)
                r.strokeColor = UIColor.systemBlue
                r.lineWidth   = 9
            }
            return r
        }

        // MARK: Annotation view

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MotoPin:
                let v = map.dequeueReusableAnnotationView(withIdentifier: "moto")
                        ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "moto")
                v.annotation     = annotation
                v.canShowCallout = false
                v.image          = motoPinImage()
                v.layer.zPosition = 999
                return v
            case let t as TurnPin:
                let v = map.dequeueReusableAnnotationView(withIdentifier: "turn")
                        ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "turn")
                v.annotation    = annotation
                v.canShowCallout = true
                v.image          = turnPinImage(t)
                v.centerOffset   = CGPoint(x: 0, y: -(t.isPrimary ? 22 : 16))
                return v
            case let w as WaypointPin:
                let v = map.dequeueReusableAnnotationView(withIdentifier: "wp")
                        ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "wp")
                v.annotation    = annotation
                v.canShowCallout = true
                v.image          = waypointPinImage(w)
                return v
            default: return nil
            }
        }

        // MARK: Icona moto — sagoma di moto stilizzata che marca la posizione.
        // Niente cerchio: solo la moto arancione con un contorno bianco, così
        // resta leggibile su qualsiasi sfondo della mappa.
        private func motoPinImage() -> UIImage {
            let S: CGFloat = 50
            let cfg = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
            let glyph = UIImage(systemName: "motorcycle", withConfiguration: cfg)
            return UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { _ in
                guard let glyph else { return }
                let origin = CGPoint(x: (S - glyph.size.width) / 2,
                                     y: (S - glyph.size.height) / 2)
                let rect = CGRect(origin: origin, size: glyph.size)
                // Contorno bianco: la sagoma ridisegnata sfalsata attorno
                let white = glyph.withTintColor(.white, renderingMode: .alwaysOriginal)
                for dx in [-2.5, 0, 2.5] {
                    for dy in [-2.5, 0, 2.5] where !(dx == 0 && dy == 0) {
                        white.draw(in: rect.offsetBy(dx: dx, dy: dy))
                    }
                }
                // Moto arancione sopra il contorno
                glyph.withTintColor(.systemOrange, renderingMode: .alwaysOriginal).draw(in: rect)
            }
        }

        // MARK: Pin svolta
        private func turnPinImage(_ t: TurnPin) -> UIImage {
            let S: CGFloat = t.isPrimary ? 42 : 30
            return UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { _ in
                UIColor.systemOrange.withAlphaComponent(t.isPrimary ? 1.0 : 0.65).setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: S-4, height: S-4)).fill()
                UIColor.white.setStroke()
                let b = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: S-4, height: S-4))
                b.lineWidth = t.isPrimary ? 2 : 1.5; b.stroke()
                let cfg = UIImage.SymbolConfiguration(pointSize: S * 0.40, weight: .bold)
                if let img = UIImage(systemName: t.direction.sfSymbol, withConfiguration: cfg)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    img.draw(at: CGPoint(x: (S - img.size.width)/2,
                                        y: (S - img.size.height)/2))
                }
            }
        }

        // MARK: Pin tappa
        private func waypointPinImage(_ w: WaypointPin) -> UIImage {
            let S: CGFloat = 30
            return UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { _ in
                let c: UIColor = w.state == .done   ? .systemGray3
                               : w.state == .active ? .systemOrange
                               : .systemBlue
                c.setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: S-4, height: S-4)).fill()
                (w.label as NSString).draw(
                    at: CGPoint(x: (S - 12)/2, y: (S - 14)/2),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11),
                                     .foregroundColor: UIColor.white])
            }
        }
    }
}

// MARK: - Annotation models

class MotoPin: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

class WaypointPin: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let label: String
    enum State { case done, active, todo }
    let state: State
    init(coordinate: CLLocationCoordinate2D, label: String, state: State) {
        self.coordinate = coordinate; self.title = label
        self.label = label; self.state = state
    }
}

class TurnPin: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let direction: TurnDirection
    let title: String?
    let isPrimary: Bool
    init(coordinate: CLLocationCoordinate2D, direction: TurnDirection,
         title: String, isPrimary: Bool) {
        self.coordinate = coordinate; self.direction = direction
        self.title = title; self.isPrimary = isPrimary
    }
}
