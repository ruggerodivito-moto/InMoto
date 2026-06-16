import SwiftUI
import UIKit

/// Scheda PDF di un tragitto in formato **orizzontale**: mappa grande a sinistra,
/// dati a destra. Renderizzata in PDF da `RoutePDFGenerator` (larghezza A4
/// orizzontale, altezza dinamica → pagina unica).
struct RoutePDFPage: View {
    let route: MotoRoute
    let navRoute: NavigationRoute
    let mapImage: UIImage?

    private let width = RoutePDFGenerator.pageWidth          // 842
    private let mapW = RoutePDFGenerator.mapPanelWidth        // 486
    private let mapH = RoutePDFGenerator.mapPanelHeight       // 470
    private let pad: CGFloat = 28

    private let accent = Color(red: 0.95, green: 0.50, blue: 0.07)
    private let ink = Color(white: 0.12)
    private let faint = Color(white: 0.46)

    private var totalKm: Int { max(1, Int((navRoute.totalDistanceMeters / 1000).rounded())) }
    private var nodes: [GeocodedWaypoint] { navRoute.waypoints }

    var body: some View {
        VStack(spacing: 0) {
            headerStrip
            HStack(alignment: .top, spacing: 22) {
                mapPanel
                sidePanel
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 22)
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // ── Striscia intestazione ─────────────────────────────────────────────────
    private var headerStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.north.fill").font(.system(size: 15, weight: .black))
            Text("INMOTO").font(.system(size: 16, weight: .black)).tracking(3)
            Spacer()
            Text("SCHEDA TRAGITTO · \(dateString)")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, pad)
        .padding(.vertical, 14)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.14),
                                    Color(red: 0.22, green: 0.22, blue: 0.26)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    // ── Mappa (protagonista) ──────────────────────────────────────────────────
    @ViewBuilder
    private var mapPanel: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = mapImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: mapW, height: mapH)
                    .clipped()
            } else {
                ZStack {
                    Rectangle().fill(Color(white: 0.93))
                    Label("Mappa non disponibile", systemImage: "map")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(width: mapW, height: mapH)
            }
            legendCard.padding(12)
        }
        .frame(width: mapW, height: mapH)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(white: 0.85), lineWidth: 1))
    }

    private var legendCard: some View {
        HStack(spacing: 12) {
            legendDot(.green, "Partenza")
            legendDot(accent, "Nodo")
            legendDot(.red, "Arrivo")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(white: 0.85), lineWidth: 0.5))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink)
        }
    }

    // ── Colonna destra ────────────────────────────────────────────────────────
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock
            statsGrid
            if !route.descrizione.isEmpty { descriptionBlock }
            nodesBlock
            Spacer(minLength: 0)
            footer
        }
        .frame(width: width - mapW - 22 - pad * 2, alignment: .topLeading)
        .frame(minHeight: mapH, alignment: .topLeading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.nome)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(ink)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                pill(icon: route.transportMode.icon, text: route.transportMode.label)
                pill(icon: "arrow.left.arrow.right",
                     text: "\(shortName(route.partenza)) → \(shortName(route.arrivo))")
            }
        }
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(accent, in: Capsule())
    }

    // ── Statistiche 2×2 ───────────────────────────────────────────────────────
    private var statsGrid: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                statChip(value: "\(totalKm)", unit: "km", label: "Distanza", icon: "road.lanes")
                statChip(value: navRoute.formattedDuration, unit: "", label: "Durata", icon: "clock")
            }
            HStack(spacing: 9) {
                statChip(value: "\(nodes.count)", unit: "", label: "Nodi", icon: "mappin.and.ellipse")
                statChip(value: route.difficolta, unit: "", label: "Difficoltà", icon: "speedometer")
            }
        }
    }

    private func statChip(value: String, unit: String, label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 16, weight: .heavy)).foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 9, weight: .semibold)).foregroundStyle(faint)
                    }
                }
                Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(faint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 11))
    }

    // ── Descrizione ─────────────────────────────────────────────────────────
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Descrizione")
            Text(route.descrizione)
                .font(.system(size: 10.5)).foregroundStyle(Color(white: 0.28)).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Nodi ────────────────────────────────────────────────────────────────
    private var nodesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Nodi del percorso (\(nodes.count))")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { i, wp in
                    nodeRow(index: i, wp: wp)
                    if i < nodes.count - 1 { connector(legInfo: legInfo(at: i)) }
                }
            }
        }
    }

    private func nodeRow(index: Int, wp: GeocodedWaypoint) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(index == 0 ? Color.green
                          : index == nodes.count - 1 ? Color.red : accent)
                    .frame(width: 24, height: 24)
                Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(shortName(wp.name)).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                if let note = wp.note, !note.isEmpty {
                    Text(note).font(.system(size: 10)).italic().foregroundStyle(faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func connector(legInfo: String?) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(Color(white: 0.85)).frame(width: 2, height: 15).padding(.leading, 11)
            if let legInfo {
                Text(legInfo).font(.system(size: 9, weight: .semibold)).foregroundStyle(faint)
            }
            Spacer()
        }
    }

    // ── Footer ──────────────────────────────────────────────────────────────
    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(Color(white: 0.9)).frame(height: 1)
            Text(metaLine).font(.system(size: 9)).foregroundStyle(faint).lineLimit(2)
            Text("Generato da InMoto").font(.system(size: 9, weight: .semibold)).foregroundStyle(accent)
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    private func sectionTitle(_ t: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 3, height: 13)
            Text(t.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(ink)
        }
    }

    private func legInfo(at i: Int) -> String? {
        guard i < navRoute.legs.count else { return nil }
        let leg = navRoute.legs[i]
        let km = leg.distanceMeters / 1000
        let min = Int(leg.durationSeconds / 60)
        if km < 0.1 && min < 1 { return nil }
        return String(format: "%.1f km · %d min", km, min)
    }

    private var metaLine: String {
        [route.regione, route.fonte, route.stagione].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }
}
