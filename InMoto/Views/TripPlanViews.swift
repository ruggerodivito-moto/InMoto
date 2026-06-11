import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// Dettaglio viaggio: timeline tappe/pause, ogni tappa si avvia nel navigatore
// ═════════════════════════════════════════════════════════════════════════════

struct TripPlanDetailView: View {
    let plan: TripPlan
    @State private var stageToNavigate: MotoRoute?

    var body: some View {
        List {
            // ── Intestazione ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if !plan.sottotitolo.isEmpty {
                        Text(plan.sottotitolo)
                            .font(.headline)
                    }
                    HStack(spacing: 14) {
                        if plan.totaleKm > 0 {
                            Label("\(plan.totaleKm) km", systemImage: "road.lanes")
                        }
                        if plan.totaleMin > 0 {
                            Label(plan.durataFormattata, systemImage: "clock")
                        }
                        Label("\(plan.tappe.count) tappe", systemImage: "flag.checkered")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // ── Timeline ─────────────────────────────────────────────────────
            Section {
                ForEach(plan.items) { item in
                    TripItemRow(item: item) {
                        stageToNavigate = plan.motoRoute(for: item)
                    }
                }
            } header: {
                Text("Programma")
            }

            // ── Nota finale ───────────────────────────────────────────────────
            if !plan.notaFinale.isEmpty {
                Section {
                    Text(plan.notaFinale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Per il ritorno")
                }
            }
        }
        .navigationTitle(plan.nome)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $stageToNavigate) { route in
            DownloadPreparationView(route: route)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Riga della timeline (tappa / pausa / arrivo)
// ═════════════════════════════════════════════════════════════════════════════

struct TripItemRow: View {
    let item: TripPlanItem
    var onStart: (() -> Void)? = nil   // nil = anteprima senza pulsante

    @State private var showWaypoints = false

    private var navigable: Bool { item.kind == .tappa && item.waypointsGmaps.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.titolo)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(badgeColor)
                        Spacer()
                        if !item.orarioFormattato.isEmpty {
                            Text(item.orarioFormattato)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.nome)
                        .font(.subheadline.weight(.medium))

                    if item.kind == .tappa, item.km > 0 || item.durataMin > 0 {
                        HStack(spacing: 10) {
                            if item.km > 0 {
                                Text("\(item.km) km")
                            }
                            if item.durataMin > 0 {
                                let h = item.durataMin / 60, m = item.durataMin % 60
                                Text(h > 0 ? "\(h)h\(m > 0 ? " \(m)'" : "")" : "\(m)'")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !item.nota.isEmpty {
                        Label(item.nota, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Punti di passaggio (solo tappe, espandibili)
            if item.kind == .tappa, item.tappeNomi.count > 2 {
                Button {
                    withAnimation { showWaypoints.toggle() }
                } label: {
                    Label("\(item.tappeNomi.count) punti di passaggio",
                          systemImage: showWaypoints ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 44)

                if showWaypoints {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(item.tappeNomi.enumerated()), id: \.offset) { i, name in
                            HStack(spacing: 8) {
                                Text("\(i + 1)")
                                    .font(.caption2.weight(.bold))
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.orange.opacity(0.18)))
                                Text(name.components(separatedBy: ",").first ?? name)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.leading, 44)
                }
            }

            // Pulsante avvio navigazione
            if navigable, let onStart {
                Button(action: onStart) {
                    Label("Avvia navigazione", systemImage: "location.north.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.leading, 44)
            } else if item.kind == .tappa, !navigable {
                Label("Tappa senza percorso riconosciuto", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 6)
    }

    private var badgeColor: Color {
        switch item.kind {
        case .tappa:  return .orange
        case .pausa:  return .teal
        case .arrivo: return .green
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor.opacity(0.15))
                .frame(width: 34, height: 34)
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(badgeColor)
        }
    }

    private var iconName: String {
        switch item.kind {
        case .tappa:  return "point.topleft.down.curvedto.point.bottomright.up"
        case .pausa:  return "cup.and.saucer.fill"
        case .arrivo: return "flag.checkered"
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Import roadbook: incolla il testo → anteprima → salva
// ═════════════════════════════════════════════════════════════════════════════

struct RoadbookImportView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var isParsing = false
    @State private var parsedPlan: TripPlan?
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .onChange(of: rawText) { _ in
                            parsedPlan = nil
                            errorMsg = nil
                        }
                } header: {
                    Text("Incolla il roadbook")
                } footer: {
                    Text("Formato: NOME, poi sezioni TAPPA n / PAUSA n / ARRIVO. Ogni sezione può contenere link Google Maps, orari (7:30 - 9:45), distanze (148Km) e durate (2h 15'). Le note tra parentesi vengono conservate.")
                }

                Section {
                    Button(action: analizza) {
                        HStack {
                            Spacer()
                            if isParsing {
                                ProgressView().padding(.trailing, 8)
                            } else {
                                Image(systemName: "doc.text.magnifyingglass")
                            }
                            Text(isParsing ? "Lettura link in corso…" : "Analizza roadbook")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                    .tint(.indigo)

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                if let plan = parsedPlan {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.nome).font(.headline)
                            if !plan.sottotitolo.isEmpty {
                                Text(plan.sottotitolo).font(.subheadline).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                if plan.totaleKm > 0 { Text("\(plan.totaleKm) km") }
                                if plan.totaleMin > 0 { Text(plan.durataFormattata) }
                                Text("\(plan.tappe.count) tappe")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        ForEach(plan.items) { item in
                            TripItemRow(item: item)
                        }

                        Button {
                            store.saveTripPlan(plan)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "bookmark.fill")
                                Text("Salva viaggio").fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } header: {
                        Label("Viaggio riconosciuto", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Importa roadbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func analizza() {
        isParsing = true
        errorMsg = nil
        Task {
            let plan = await RoadbookParser.parse(rawText)
            await MainActor.run {
                isParsing = false
                if let plan {
                    parsedPlan = plan
                    let broken = plan.tappe.filter { $0.waypointsGmaps.count < 2 }
                    if !broken.isEmpty {
                        errorMsg = "Attenzione: \(broken.map { $0.titolo }.joined(separator: ", ")) senza percorso riconosciuto (link mancante o non leggibile)."
                    }
                } else {
                    errorMsg = "Nessuna sezione TAPPA trovata nel testo. Controlla il formato."
                }
            }
        }
    }
}
