import SwiftUI

struct RouteCardView: View {
    let route: MotoRoute
    var isCustom: Bool { route.isCustom == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if isCustom {
                        Label("Percorso su misura", systemImage: "wand.and.sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.gradient)
                            .clipShape(Capsule())
                    }
                    Text(route.nome)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                DiffBadge(level: route.difficolta)
            }

            // Stelle
            StarRow(value: route.stelle)

            // Partenza → Arrivo
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.indigo)
                    .font(.caption)
                Text(route.partenza)
                    .fontWeight(.medium)
                    .font(.subheadline)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(route.arrivo)
                    .fontWeight(.medium)
                    .font(.subheadline)
            }
            .lineLimit(1)

            // Meta
            HStack(spacing: 16) {
                Label(isCustom ? "~\(route.km) km" : "\(route.km) km",
                      systemImage: "road.lanes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(isCustom ? "~\(route.durataFormattata)" : route.durataFormattata,
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(route.regione, systemImage: "map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Tags
            if !route.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(route.tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(isCustom
            ? AnyView(RoundedRectangle(cornerRadius: 14)
                .fill(.background)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange, lineWidth: 2)))
            : AnyView(RoundedRectangle(cornerRadius: 14)
                .fill(.background)
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)))
        .padding(.horizontal)
    }
}

// ── Stelle ───────────────────────────────────────────────────────────────────
struct StarRow: View {
    let value: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: starImageName(for: i))
                    .font(.caption)
                    .foregroundStyle(value >= Double(i) - 0.25 ? .yellow : .gray.opacity(0.3))
            }
            Text(String(format: "%.1f", value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 3)
        }
    }

    private func starImageName(for i: Int) -> String {
        let d = Double(i)
        if value >= d       { return "star.fill" }
        if value >= d - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// ── Badge difficoltà ─────────────────────────────────────────────────────────
struct DiffBadge: View {
    let level: String
    var color: Color {
        switch level.lowercased() {
        case "facile":    return .green
        case "difficile": return .red
        default:          return .orange
        }
    }
    var body: some View {
        Text(level.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
