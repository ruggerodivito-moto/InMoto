import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: RouteStore

    @State private var partenza  = ""
    @State private var arrivo    = ""
    @State private var regione   = ""
    @State private var kmMax     = ""
    @State private var durataMax = 0      // minuti, 0 = qualsiasi

    @State private var composedRoute: MotoRoute?
    @State private var relatedRoutes: [MotoRoute] = []
    @State private var isComposing = false
    @State private var composeError: String?
    @State private var hasSearched = false

    private let durataOptions = [0, 60, 120, 180, 240, 360]
    private let durataLabels  = ["Qualsiasi", "1h", "2h", "3h", "4h", "6h"]

    private var canSearch: Bool {
        !partenza.trimmingCharacters(in: .whitespaces).isEmpty ||
        !arrivo.trimmingCharacters(in: .whitespaces).isEmpty   ||
        !regione.isEmpty ||
        !kmMax.trimmingCharacters(in: .whitespaces).isEmpty    ||
        durataMax > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Filtri ─────────────────────────────────────────────────
                Section {
                    Picker("Regione", selection: $regione) {
                        Text("— Tutte le regioni —").tag("")
                        ForEach(store.regions, id: \.self) { r in Text(r).tag(r) }
                    }
                } header: { Text("Regione") }

                Section {
                    HStack {
                        Image(systemName: "mappin.circle").foregroundStyle(.green)
                        TextField("Luogo di partenza", text: $partenza)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        TextField("Luogo di arrivo", text: $arrivo)
                            .autocorrectionDisabled()
                    }
                } header: { Text("Percorso (opzionali)") }

                Section {
                    HStack {
                        Image(systemName: "road.lanes").foregroundStyle(.indigo)
                        TextField("Km massimi (es. 150)", text: $kmMax)
                            .keyboardType(.numberPad)
                        Text("km").foregroundStyle(.secondary)
                    }
                    Picker("Durata massima", selection: $durataMax) {
                        ForEach(0..<durataOptions.count, id: \.self) { i in
                            Text(durataLabels[i]).tag(durataOptions[i])
                        }
                    }
                } header: { Text("Vincoli (opzionali)") }

                Section {
                    Button(action: cerca) {
                        HStack {
                            Spacer()
                            if isComposing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(isComposing ? "Elaborazione…" : "Cerca")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSearch || isComposing)
                    .tint(.indigo)

                    if canSearch {
                        Button("Azzera filtri", role: .destructive) { reset() }
                    }
                }

                // ── Errore compose ─────────────────────────────────────────
                if let err = composeError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                // ── Percorso su misura ─────────────────────────────────────
                if let composed = composedRoute {
                    Section {
                        NavigationLink(destination: RouteDetailView(route: composed)) {
                            RouteCardView(route: composed)
                                .padding(.horizontal, -16)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Label("Percorso su misura generato", systemImage: "wand.and.sparkles")
                            .foregroundStyle(.orange)
                    }
                }

                // ── Itinerari correlati ────────────────────────────────────
                if !relatedRoutes.isEmpty {
                    Section {
                        ForEach(relatedRoutes) { route in
                            NavigationLink(destination: RouteDetailView(route: route)) {
                                RouteCardView(route: route)
                                    .padding(.horizontal, -16)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(composedRoute != nil ? "Itinerari correlati (\(relatedRoutes.count))" : "Risultati (\(relatedRoutes.count))")
                    }
                }

                // ── Nessun risultato ───────────────────────────────────────
                if hasSearched && composedRoute == nil && relatedRoutes.isEmpty && !isComposing {
                    Section {
                        ContentUnavailableView("Nessun risultato",
                            systemImage: "map.circle",
                            description: Text("Prova a modificare i filtri o a selezionare una regione."))
                    }
                }
            }
            .navigationTitle("Cerca Itinerari")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    private func cerca() {
        hideKeyboard()
        hasSearched = true
        composeError = nil
        composedRoute = nil

        let p = partenza.trimmingCharacters(in: .whitespaces)
        let a = arrivo.trimmingCharacters(in: .whitespaces)
        let k = kmMax.trimmingCharacters(in: .whitespaces)

        // Filtro locale itinerari correlati
        relatedRoutes = store.filtered(
            regione:   regione.isEmpty ? nil : regione,
            partenza:  p.isEmpty ? nil : p,
            arrivo:    a.isEmpty ? nil : a,
            kmMax:     Int(k),
            durataMax: durataMax > 0 ? durataMax : nil
        )

        // Compose solo se c'è almeno partenza o regione
        let needsCompose = !p.isEmpty || !a.isEmpty
        guard needsCompose, AppSettings.shared.isConfigured else { return }

        isComposing = true
        Task {
            do {
                let body = ComposeRequest(
                    partenza:   p.isEmpty ? nil : p,
                    arrivo:     a.isEmpty ? nil : a,
                    regione:    regione.isEmpty ? nil : regione,
                    kmMax:      Int(k),
                    durataMax:  durataMax > 0 ? durataMax : nil
                )
                let result = try await APIService.shared.composeRoute(body)
                await MainActor.run { composedRoute = result }
            } catch {
                await MainActor.run { composeError = error.localizedDescription }
            }
            await MainActor.run { isComposing = false }
        }
    }

    private func reset() {
        partenza = ""; arrivo = ""; regione = ""; kmMax = ""; durataMax = 0
        composedRoute = nil; relatedRoutes = []; composeError = nil; hasSearched = false
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
