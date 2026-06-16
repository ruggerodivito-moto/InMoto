import SwiftUI
import UIKit

/// Impaginazione della scheda PDF di un tragitto: intestazione, mappa,
/// statistiche, descrizione, elenco tappe. Renderizzata in PDF da
/// `RoutePDFGenerator` (larghezza fissa A4, altezza dinamica → pagina unica).
struct RoutePDFPage: View {
    let route: MotoRoute
    let navRoute: NavigationRoute
    let mapImage: UIImage?

    private let width = RoutePDFGenerator.pageWidth
    private let accent = Color(red: 0.95, green: 0.55, blue: 0.10)

    private var totalKm: Int { max(1, Int((navRoute.totalDistanceMeters / 1000).rounded())) }
    private var waypoints: [GeocodedWaypoint] { navRoute.waypoints }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            mapSection
            VStack(alignment: .leading, spacing: 18) {
                statsRow
                if !route.descrizione.isEmpty { descriptionBlock }
                tappeBlock
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // ── Intestazione ────────────────────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("InMoto · Scheda tragitto")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(route.nome)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: width, alignment: .leading)
        .background(accent.gradient)
    }

    // ── Mappa ───────────────────────────────────────────────────────────────
    @ViewBuilder
    private var mapSection: some View {
        if let img = mapImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: 320)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Color(white: 0.93)).frame(width: width, height: 160)
                Label("Anteprima mappa non disponibile", systemImage: "map")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ── Statistiche ─────────────────────────────────────────────────────────
    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell(value: "\(totalKm)", unit: "km", label: "Distanza", icon: "road.lanes")
            statCell(value: navRoute.formattedDuration, unit: "", label: "Durata", icon: "clock")
            statCell(value: "\(max(0, waypoints.count))", unit: "", label: "Tappe", icon: "flag.checkered")
            statCell(value: route.difficolta, unit: "", label: "Difficoltà", icon: "speedometer")
        }
    }

    private func statCell(value: String, unit: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.gray)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ── Descrizione ─────────────────────────────────────────────────────────
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Descrizione")
            Text(route.descrizione)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.2))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Tappe ───────────────────────────────────────────────────────────────
    private var tappeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Tappe del percorso")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(waypoints.enumerated()), id: \.offset) { i, wp in
                    tappaRow(index: i, name: shortName(wp.name))
                    if i < waypoints.count - 1, let legInfo = legInfo(at: i) {
                        HStack(spacing: 6) {
                            Rectangle().fill(accent.opacity(0.4)).frame(width: 2, height: 16)
                                .padding(.leading, 12)
                            Text(legInfo)
                                .font(.system(size: 10))
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
        }
    }

    private func tappaRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(index == 0 ? Color.green
                          : index == waypoints.count - 1 ? Color.red : accent)
                    .frame(width: 26, height: 26)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black)
                .lineLimit(1)
            Spacer()
        }
    }

    // ── Footer ──────────────────────────────────────────────────────────────
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !route.tags.isEmpty {
                Text(route.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
            }
            Divider()
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
        Text(t.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(accent)
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
        [route.transportMode.label, route.regione, route.fonte, route.stagione]
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
