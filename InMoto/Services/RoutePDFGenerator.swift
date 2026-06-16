import SwiftUI
import UIKit
import MapKit
import CoreLocation

/// Genera un PDF "scheda tragitto" (mappa + statistiche + tappe) da un
/// `MotoRoute` e dalla sua `NavigationRoute`. Il file finisce in una cartella
/// temporanea, pronto per la condivisione / "Salva su File".
@MainActor
enum RoutePDFGenerator {

    static let pageWidth: CGFloat = 595   // A4 a 72 dpi

    /// Costruisce il PDF e ne restituisce l'URL (nil se fallisce).
    static func generate(route: MotoRoute, navRoute: NavigationRoute) async -> URL? {
        let mapImage = await routeImage(for: navRoute, size: CGSize(width: 1240, height: 720))

        let page = RoutePDFPage(route: route, navRoute: navRoute, mapImage: mapImage)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFileName(route.nome)).pdf")

        var ok = false
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    // MARK: - Snapshot mappa con tracciato

    /// Immagine della mappa con la polyline del percorso disegnata sopra.
    static func routeImage(for nav: NavigationRoute, size: CGSize) async -> UIImage? {
        let coords = nav.legs.flatMap { $0.polylineCoordinates }
        guard coords.count >= 2 else { return nil }

        // Riquadro che contiene tutto il tracciato, con margine
        var rect = MKMapRect.null
        for c in coords {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        let pad = max(rect.size.width, rect.size.height) * 0.18 + 1
        rect = rect.insetBy(dx: -pad, dy: -pad)

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        let nodes = nav.waypoints
        return UIGraphicsImageRenderer(size: size).image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (i, c) in coords.enumerated() {
                let pt = snapshot.point(for: c)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            // Alone bianco + tratto arancione
            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 10; path.stroke()
            UIColor.systemOrange.setStroke()
            path.lineWidth = 6; path.stroke()

            // Un segno numerato per ogni nodo del percorso
            for (i, wp) in nodes.enumerated() {
                let p = snapshot.point(for: wp.coordinate)
                let color: UIColor = i == 0 ? .systemGreen
                    : i == nodes.count - 1 ? .systemRed
                    : UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
                drawNodeMarker(at: p, number: i + 1, color: color)
            }
        }
    }

    private static func drawNodeMarker(at p: CGPoint, number: Int, color: UIColor) {
        let r: CGFloat = 16
        // Alone bianco
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: p.x - r - 3, y: p.y - r - 3,
                                    width: 2 * r + 6, height: 2 * r + 6)).fill()
        // Disco colorato
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
        // Numero
        let label = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let sz = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2), withAttributes: attrs)
    }

    private static func safeFileName(_ name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tragitto" : name
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = base.components(separatedBy: invalid).joined(separator: "-")
        return "InMoto - \(cleaned)"
    }
}

/// Sheet di condivisione del sistema (Salva su File, AirDrop, Mail, …).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
