import SwiftUI
import UIKit

/// Impaginazione della scheda PDF di un tragitto: intestazione, mappa,
/// statistiche, descrizione, elenco nodi (numerati come sulla mappa).
/// Renderizzata in PDF da `RoutePDFGenerator` (larghezza fissa A4, altezza
/// dinamica → pagina unica).
struct RoutePDFPage: View {
    let route: MotoRoute
    let navRoute: NavigationRoute
    let mapImage: UIImage?

    private let width = RoutePDFGenerator.pageWidth
    private let pagePadding: CGFloat = 30
    private let accent = Color(red: 0.95, green: 0.55, blue: 0.10)
    private let ink = Color(white: 0.13)

    private var totalKm: Int { max(1, Int((navRoute.totalDistanceMeters / 1000).rounded())) }
    private var nodes: [GeocodedWaypoint] { navRoute.waypoints }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            mapSection
            VStack(alignment: .leading, spacing: 22) {
                statsRow
                if !route.descrizione.isEmpty { descriptionBlock }
                nodesBlock
                footer
            }
            .padding(.horizontal, pagePadding)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // ── Intestazione ────────────────────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 58, height: 58)
                Image(systemName: route.transportMode.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("INMOTO · SCHEDA TRAGITTO")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.9))
                Text(route.nome)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(shortName(route.partenza))  →  \(shortName(route.arrivo))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pagePadding)
        .padding(.vertical, 24)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(colors: [accent, accent.opacity(0.78)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    // ── Mappa ───────────────────────────────────────────────────────────────
    @ViewBuilder
    private var mapSection: some View {
        if let img = mapImage {
            VStack(spacing: 0) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - pagePadding * 2, height: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(white: 0.85), lineWidth: 1)
                    )
            }
            .padding(.horizontal, pagePadding)
            .padding(.top, 18)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.94))
                Label("Anteprima mappa non disponibile", systemImage: "map")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(width: width - pagePadding * 2, height: 150)
            .padding(.horizontal, pagePadding)
            .padding(.top, 18)
        }
    }

    // ── Statistiche ─────────────────────────────────────────────────────────
    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(totalKm)", unit: "km", label: "Distanza", icon: "road.lanes")
            statDivider
            statCell(value: navRoute.formattedDuration, unit: "", label: "Durata", icon: "clock")
            statDivider
            statCell(value: "\(nodes.count)", unit: "", label: "Nodi", icon: "mappin.and.ellipse")
            statDivider
            statCell(value: route.transportMode.label, unit: "", label: "Mezzo", icon: route.transportMode.icon)
        }
        .padding(.vertical, 14)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statDivider: some View {
        Rectangle().fill(Color(white: 0.88)).frame(width: 1, height: 38)
    }

    private func statCell(value: String, unit: String, label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10, weight: .medium)).foregroundStyle(.gray)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Descrizione ─────────────────────────────────────────────────────────
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Descrizione")
            Text(route.descrizione)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.25))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Nodi ────────────────────────────────────────────────────────────────
    private var nodesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Nodi del percorso")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { i, wp in
                    nodeRow(index: i, wp: wp)
                    if i < nodes.count - 1 {
                        connector(legInfo: legInfo(at: i))
                    }
                }
            }
        }
    }

    private func nodeRow(index: Int, wp: GeocodedWaypoint) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle()
                    .fill(index == 0 ? Color.green
                          : index == nodes.count - 1 ? Color.red : accent)
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shortName(wp.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                if let note = wp.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(Color(white: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func connector(legInfo: String?) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent.opacity(0.35))
                .frame(width: 2, height: 18)
                .padding(.leading, 13)
            if let legInfo {
                Text(legInfo)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color(white: 0.95))
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // ── Footer ──────────────────────────────────────────────────────────────
    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !route.tags.isEmpty {
                Text(route.tags.map { "#\($0)" }.joined(separator: "   "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
            }
            Rectangle().fill(Color(white: 0.9)).frame(height: 1)
            HStack {
                Text(metaLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Spacer()
                Text("Generato da InMoto · \(dateString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    private func sectionTitle(_ t: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 3, height: 13)
            Text(t.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(ink)
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
        [route.regione, route.fonte, route.stagione]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
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
