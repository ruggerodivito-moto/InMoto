import SwiftUI

// ── Schermata principale "Tragitti importati" ────────────────────────────────
struct ImportedRoutesView: View {
    @EnvironmentObject var store:    RouteStore
    @EnvironmentObject var appState: AppState
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if store.personalRoutes.isEmpty {
                    emptyState
                } else {
                    routeList
                }
            }
            .navigationTitle("Tragitti personali")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportRouteView()
            }
        }
    }

    // ── Stato vuoto ──────────────────────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bookmark.slash")
                .font(.system(size: 60))
                .foregroundStyle(.indigo.opacity(0.4))
            Text("Nessun tragitto personale")
                .font(.title2.weight(.semibold))
            Text("Importa i tuoi tragitti preferiti\ncon le tappe che vuoi percorrere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button {
                showImport = true
            } label: {
                Label("Importa tragitto", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            Spacer()
        }
        .padding()
    }

    // ── Lista tragitti personali ─────────────────────────────────────────────
    private var routeList: some View {
        List {
            ForEach(store.personalRoutes) { route in
                NavigationLink(destination: RouteDetailView(route: route)) {
                    RouteCardView(route: route)
                        .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete { offsets in
                offsets.forEach { i in
                    store.deletePersonalRoute(store.personalRoutes[i])
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
    }
}

// ── Form importazione ────────────────────────────────────────────────────────
struct ImportRouteView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var routeName     = ""
    @State private var waypointsText = ""
    @State private var preview:  MotoRoute? = nil
    @State private var errorMsg: String?    = nil
    @State private var saved = false

    private var parsedWaypoints: [String] {
        waypointsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canVerify: Bool {
        !routeName.trimmingCharacters(in: .whitespaces).isEmpty &&
        parsedWaypoints.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Nome ──────────────────────────────────────────────────────
                Section {
                    TextField("Es. Giro delle Langhe", text: $routeName)
                        .autocorrectionDisabled()
                } header: { Text("Nome del tragitto") }

                // ── Tappe ─────────────────────────────────────────────────────
                Section {
                    TextEditor(text: $waypointsText)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .autocapitalizationDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: waypointsText) { _ in
                            preview  = nil
                            errorMsg = nil
                        }
                } header: {
                    Text("Tappe (una per riga)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inserisci ogni tappa su una riga separata.")
                        Text("Esempio:")
                            .foregroundStyle(.secondary)
                        Text("Genova\nPasso del Turchino\nAlbenga\nSavona")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                    }
                }

                // ── Verifica ──────────────────────────────────────────────────
                Section {
                    Button(action: verifica) {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.magnifyingglass")
                            Text("Verifica tappe")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canVerify)
                    .tint(.indigo)

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                // ── Anteprima + salva ─────────────────────────────────────────
                if let prev = preview {
                    Section {
                        RouteCardView(route: prev)
                            .padding(.horizontal, -16)
                            .padding(.vertical, 4)

                        // Riepilogo tappe
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(prev.tappe.enumerated()), id: \.offset) { i, tappa in
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(i == 0 ? Color.green
                                                  : i == prev.tappe.count - 1 ? Color.red
                                                  : Color.indigo)
                                            .frame(width: 22, height: 22)
                                        Text("\(i + 1)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                    Text(tappa)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        Button(action: salva) {
                            HStack {
                                Spacer()
                                Image(systemName: "bookmark.fill")
                                Text("Salva nel tuo elenco")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                    } header: {
                        Label("Anteprima tragitto", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Importa tragitto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    // ── Logica ───────────────────────────────────────────────────────────────
    private func verifica() {
        let wps = parsedWaypoints
        guard wps.count >= 2 else {
            errorMsg = "Inserisci almeno 2 tappe"
            return
        }
        guard !routeName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMsg = "Dai un nome al tragitto"
            return
        }
        errorMsg = nil

        // Costruisce il tragitto di anteprima
        // I waypoints per Google Maps vengono formattati con ", Italy" per la geocodifica
        let gWaypoints = wps.map { wp -> String in
            let trimmed = wp.trimmingCharacters(in: .whitespaces)
            return trimmed.lowercased().contains("italy") ? trimmed : "\(trimmed), Italy"
        }

        preview = MotoRoute(
            id: UUID().uuidString,
            nome: routeName.trimmingCharacters(in: .whitespaces),
            partenza: wps.first!,
            arrivo: wps.last!,
            regione: "",
            km: 0,
            durataMin: 0,
            difficolta: "Media",
            stelle: 0,
            descrizione: "Tragitto personale con \(wps.count) tapp\(wps.count == 1 ? "a" : "e").",
            tappe: wps,
            waypointsGmaps: gWaypoints,
            tags: ["personale"],
            fonte: "Importato",
            stagione: "Tutto l'anno",
            isCustom: true
        )
    }

    private func salva() {
        guard let route = preview else { return }
        store.savePersonalRoute(route)
        dismiss()
    }
}

// Estensione per disabilitare autocapitalizzazione su TextEditor
private extension View {
    func autocapitalizationDisabled() -> some View {
        self
    }
}
