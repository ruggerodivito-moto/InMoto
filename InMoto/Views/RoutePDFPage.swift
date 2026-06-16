import SwiftUI
import UIKit

/// Scheda PDF di un tragitto: header, mappa "hero" a tutta larghezza con tutti
/// i nodi, statistiche, descrizione, timeline dei nodi. Renderizzata in PDF da
/// `RoutePDFGenerator` (larghezza A4, altezza dinamica → pagina unica).
struct RoutePDFPage: View {
    let route: MotoRoute
    let navRoute: NavigationRoute
    let mapImage: UIImage?

    private let width = RoutePDFGenerator.pageWidth
    private let pad: CGFloat = 32
    private let accent = Color(red: 0.95, green: 0.50, blue: 0.07)
    private let ink = Color(white: 0.12)
    private let faint = Color(white: 0.46)

    private var totalKm: Int { max(1, Int((navRoute.totalDistanceMeters / 1000).rounded())) }
    private var nodes: [GeocodedWaypoint] { navRoute.waypoints }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            mapHero
            legend
            VStack(alignment: .leading, spacing: 24) {
                statsCard
                if !route.descrizione.isEmpty { descriptionBlock }
                nodesBlock
                footer
            }
            .padding(.horizontal, pad)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // ── Intestazione ────────────────────────────────────────────────────────
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .black))
                Text("INMOTO")
                    .font(.system(size: 14, weight: .black))
                    .tracking(3)
                Spacer()
                Text("SCHEDA TRAGITTO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)

            Text(route.nome)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 8) {
                pill(icon: route.transportMode.icon, text: route.transportMode.label)
                pill(icon: "arrow.left.arrow.right",
                     text: "\(shortName(route.partenza)) → \(shortName(route.arrivo))")
            }
        }
        .padding(.horizontal, pad)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.15),
                                    Color(red: 0.20, green: 0.20, blue: 0.23)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(accent, in: Capsule())
    }

    // ── Mappa hero (a tutta larghezza) ────────────────────────────────────────
    @ViewBuilder
    private var mapHero: some View {
        if let img = mapImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: 360)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Color(white: 0.93))
                Label("Anteprima mappa non disponibile", systemImage: "map")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(width: width, height: 150)
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem(color: accent, filled: true, text: "Nodi del tracciato")
            legendItem(color: .green, filled: true, text: "Partenza", number: "1")
            legendItem(color: .red, filled: true, text: "Arrivo", number: "\(nodes.count)")
            Spacer()
        }
        .padding(.horizontal, pad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(Color(white: 0.96))
    }

    private func legendItem(color: Color, filled: Bool, text: String, number: String? = nil) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(color).frame(width: number == nil ? 9 : 16, height: number == nil ? 9 : 16)
                if let number { Text(number).font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
            }
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(faint)
        }
    }

    // ── Statistiche ───────────────────────────────────────────────────────────
    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(value: "\(totalKm)", unit: "km", label: "Distanza", icon: "road.lanes")
            statDivider
            statCell(value: navRoute.formattedDuration, unit: "", label: "Durata", icon: "clock")
            statDivider
            statCell(value: "\(nodes.count)", unit: "", label: "Nodi", icon: "mappin.and.ellipse")
            statDivider
            statCell(value: route.transportMode.label, unit: "", label: "Mezzo", icon: route.transportMode.icon)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.9), lineWidth: 1))
    }

    private var statDivider: some View {
        Rectangle().fill(Color(white: 0.9)).frame(width: 1, height: 40)
    }

    private func statCell(value: String, unit: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 19, weight: .heavy)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(faint)
                }
            }
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(faint)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Descrizione ─────────────────────────────────────────────────────────
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Descrizione")
            Text(route.descrizione)
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.25))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Nodi ────────────────────────────────────────────────────────────────
    private var nodesBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(index == 0 ? Color.green
                          : index == nodes.count - 1 ? Color.red : accent)
                    .frame(width: 30, height: 30)
                Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shortName(wp.name)).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                if let note = wp.note, !note.isEmpty {
                    Text(note).font(.system(size: 11)).italic().foregroundStyle(faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func connector(legInfo: String?) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(white: 0.85)).frame(width: 2, height: 20).padding(.leading, 14)
            if let legInfo {
                Text(legInfo)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(faint)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color(white: 0.96), in: Capsule())
            }
            Spacer()
        }
    }

    // ── Footer ──────────────────────────────────────────────────────────────
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !route.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(route.tags, id: \.self) { tag in
                        Text(tag.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            Rectangle().fill(Color(white: 0.9)).frame(height: 1)
            HStack {
                Text(metaLine).font(.system(size: 10)).foregroundStyle(faint)
                Spacer()
                Text("Generato da InMoto · \(dateString)").font(.system(size: 10)).foregroundStyle(faint)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    private func sectionTitle(_ t: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 4, height: 15)
            Text(t.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(ink)
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
