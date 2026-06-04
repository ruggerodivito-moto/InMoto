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
        // Ricarica overlay e pin solo quando cambia tratta o step
        let key = currentLegIndex * 10_000 + currentStepIndex
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            reloadRoute(map)
            if !isFollowingUser { showOverview(map) }
        }

        // Icona moto: crea al primo fix GPS, poi aggiorna coordinate via KVO
        if let loc = userLocation {
            if let ann = context.coordinator.motoPin {
                ann.coordinate = loc.coordinate
            } else {
                let ann = MotoPin(coordinate: loc.coordinate)
                map.addAnnotation(ann)
                context.coordinator.motoPin = ann
            }
        }

        // Camera: segui l'utente solo in modalità navigazione attiva
        guard isFollowingUser, let loc = userLocation else { return }

        let hdg = userHeading.flatMap { $0 >= 0 ? $0 : nil }
                  ?? (loc.course >= 0 ? loc.course : map.camera.heading)

        // pitch=20° → la mappa è quasi in pianta, il percorso è ben visibile
        // altitude=700m → mostra ~1.5km di strada davanti
        let cam = MKMapCamera()
        cam.centerCoordinate = loc.coordinate
        cam.heading          = hdg
        cam.pitch            = 20
        cam.altitude         = 700
        map.setCamera(cam, animated: false)
    }

    // MARK: - Percorso

    private func reloadRoute(_ map: MKMapView) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MotoPin) })

        // Linee percorso
        for (i, leg) in navRoute.legs.enumerated() {
            let pts = leg.polylineCoordinates
            guard pts.count >= 2 else { continue }

            // Bordo bianco (disegnato per primo, più largo → crea il contorno)
            let border = MKPolyline(coordinates: pts, count: pts.count)
            border.title = "border"
            map.addOverlay(border, level: .aboveRoads)

            // Linea colorata sopra il bordo
            let line = MKPolyline(coordinates: pts, count: pts.count)
            line.title = i < currentLegIndex  ? "done"
                       : i == currentLegIndex ? "active"
                       : "todo"
            map.addOverlay(line, level: .aboveRoads)
        }

        // Pin tappe principali
        for (i, wp) in navRoute.waypoints.enumerated() {
            map.addAnnotation(WaypointPin(
                coordinate: wp.coordinate,
                label: "\(i + 1)",
                state: i < currentLegIndex ? .done : i == currentLegIndex ? .active : .todo
            ))
        }

        // Marcatori prossime 2 svolte
        guard currentLegIndex < navRoute.legs.count else { return }
        let steps = navRoute.legs[currentLegIndex].steps
        let from  = min(currentStepIndex, steps.count - 1)
        var shown = 0
        for i in from..<steps.count where shown < 2 {
            let s = steps[i]
            guard !s.instruction.isEmpty else { continue }
            let dir = TurnDirection.parse(s.instruction)
            guard dir != .straight || i == from else { continue }
            map.addAnnotation(TurnPin(
                coordinate: s.coordinate,
                direction: dir,
                title: s.instruction,
                isPrimary: shown == 0
            ))
            shown += 1
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

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapKitView
        var lastKey = -1
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
                r.lineWidth   = 14
            case "active":
                r.strokeColor = UIColor.systemBlue
                r.lineWidth   = 10
            case "todo":
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.45)
                r.lineWidth   = 8
            default: // done
                r.strokeColor = UIColor.systemGray4
                r.lineWidth   = 7
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

        // MARK: Icona moto — freccia di navigazione, punta sempre in su
        // (la mappa ruota con il heading, quindi la freccia segue la direzione di marcia)
        private func motoPinImage() -> UIImage {
            let S: CGFloat = 56
            return UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { _ in
                // Alone bianco (shadow)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: S, height: S)).fill()
                // Cerchio arancione
                UIColor.systemOrange.setFill()
                UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: S-6, height: S-6)).fill()
                // Freccia di navigazione bianca che punta in su
                // (corpo + coda a V, classico stile navigatore)
                let arrow = UIBezierPath()
                let cx = S / 2
                arrow.move(to:     CGPoint(x: cx,      y: 9))       // punta
                arrow.addLine(to:  CGPoint(x: cx + 14, y: S - 12))  // basso destra
                arrow.addLine(to:  CGPoint(x: cx,      y: S - 20))  // rientro centrale
                arrow.addLine(to:  CGPoint(x: cx - 14, y: S - 12))  // basso sinistra
                arrow.close()
                UIColor.white.setFill()
                arrow.fill()
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
