import SwiftUI

// Fase 1 — schermata riepilogo percorso calcolato.
// La mappa GPS con avanzamento automatico arriverà nella Fase 2.
struct NavigatorView: View {
    let navRoute: NavigationRoute
    let motoRoute: MotoRoute

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                successHeader
                    .padding(.top, 8)
                summaryCard
                    .padding(.horizontal)
                legsSection
                    .padding(.horizontal)
                phase2Notice
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(navRoute.routeName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sezioni

    private var successHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Percorso pronto")
                .font(.title2.weight(.semibold))
            Text("\(navRoute.legs.count) tratt\(navRoute.legs.count == 1 ? "o" : "i") calcolat\(navRoute.legs.count == 1 ? "o" : "i") — salvato offline")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            statCell(value: navRoute.formattedDistance, label: "Distanza")
            Divider().frame(height: 44)
            statCell(value: navRoute.formattedDuration, label: "Durata")
            Divider().frame(height: 44)
            statCell(value: "\(navRoute.waypoints.count)", label: "Tappe")
        }
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var legsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tratte")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 12)

            ForEach(Array(navRoute.legs.enumerated()), id: \.offset) { i, leg in
                legRow(index: i, leg: leg)
                if i < navRoute.legs.count - 1 {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var phase2Notice: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)
            Text("La mappa con navigazione GPS e avanzamento automatico tappe arriva nella Fase 2.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Componenti

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func legRow(index: Int, leg: RouteLeg) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(shortName(leg.fromName))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("→ \(shortName(leg.toName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.0f km", leg.distanceMeters / 1000))
                    .font(.caption.weight(.medium))
                Text(formatDuration(leg.durationSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func shortName(_ full: String) -> String {
        full.components(separatedBy: ",").first ?? full
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m) min" }
        return "\(h)h \(m)min"
    }
}
