import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: RouteStore

    @State private var partenza   = ""
    @State private var arrivo     = ""
    @State private var regione    = ""
    @State private var kmMax      = ""
    @State private var durataMax  = 0

    @State private var partenzaSugg: [String] = []
    @State private var arrivoSugg:   [String] = []

    @State private var composedRoute: MotoRoute?
    @State private var relatedRoutes: [MotoRoute] = []
    @State private var isComposing  = false
    @State private var composeError: String?
    @State private var hasSearched  = false

    private let durataOptions = [0, 60, 120, 180, 240, 360]
    private let durataLabels  = ["Qualsiasi", "1h", "2h", "3h", "4h", "6h"]

    private var canSearch: Bool {
        !partenza.trimmingCharacters(in: .whitespaces).isEmpty ||
        !arrivo.trimmingCharacters(in: .whitespaces).isEmpty   ||
        !regione.isEmpty ||
        !kmMax.trimmingCharacters(in: .whitespaces).isEmpty    ||
        durataMax > 0
    }

    // ── Filtro suggerimenti ──────────────────────────────────────────────────
    private func sugg(for text: String) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return store.allLocations
            .filter { $0.localizedCaseInsensitiveContains(q) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Regione ──────────────────────────────────────────────────
                Section {
                    Picker("Regione", selection: $regione) {
                        Text("— Tutte le regioni —").tag("")
                        ForEach(store.regions, id: \.self) { r in Text(r).tag(r) }
                    }
                } header: { Text("Regione") }

                // ── Partenza ─────────────────────────────────────────────────
                Section {
                    HStack {
                        Image(systemName: "mappin.circle").foregroundStyle(.green)
                        TextField("Luogo di partenza", text: $partenza)
                            .autocorrectionDisabled()
                            .onChange(of: partenza) { _ in
                                partenzaSugg = sugg(for: partenza)
                            }
                        if !partenza.isEmpty {
                            Button { partenza = ""; partenzaSugg = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(partenzaSugg, id: \.self) { s in
                        Button {
                            partenza = s
                            partenzaSugg = []
                            hideKeyboard()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(s)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Partenza") }

                // ── Arrivo ───────────────────────────────────────────────────
                Section {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        TextField("Luogo di arrivo", text: $arrivo)
                            .autocorrectionDisabled()
                            .onChange(of: arrivo) { _ in
                                arrivoSugg = sugg(for: arrivo)
                            }
                        if !arrivo.isEmpty {
                            Button { arrivo = ""; arrivoSugg = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(arrivoSugg, id: \.self) { s in
                        Button {
                            arrivo = s
                            arrivoSugg = []
                            hideKeyboard()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                Text(s)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Arrivo") }

                // ── Vincoli ──────────────────────────────────────────────────
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

                // ── Bottoni ──────────────────────────────────────────────────
                Section {
                    Button(action: cerca) {
                        HStack {
                            Spacer()
                            if isComposing { ProgressView().padding(.trailing, 8) }
                            else { Image(systemName: "magnifyingglass") }
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

                // ── Errore compose ───────────────────────────────────────────
                if let err = composeError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                // ── Percorso su misura ───────────────────────────────────────
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

                // ── Risultati ────────────────────────────────────────────────
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
                        Text(composedRoute != nil
                             ? "Itinerari correlati (\(relatedRoutes.count))"
                             : "Risultati (\(relatedRoutes.count))")
                    }
                }

                // ── Nessun risultato ─────────────────────────────────────────
                if hasSearched && composedRoute == nil && relatedRoutes.isEmpty && !isComposing {
                    Section {
                        ContentUnavailableView("Nessun risultato",
                            systemImage: "map.circle",
                            description: Text("Prova a modificare i filtri."))
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
        hasSearched    = true
        composeError   = nil
        composedRoute  = nil
        partenzaSugg   = []
        arrivoSugg     = []

        let p = partenza.trimmingCharacters(in: .whitespaces)
        let a = arrivo.trimmingCharacters(in: .whitespaces)
        let k = kmMax.trimmingCharacters(in: .whitespaces)

        relatedRoutes = store.filtered(
            regione:   regione.isEmpty ? nil : regione,
            partenza:  p.isEmpty ? nil : p,
            arrivo:    a.isEmpty ? nil : a,
            kmMax:     Int(k),
            durataMax: durataMax > 0 ? durataMax : nil
        )

        let needsCompose = !p.isEmpty || !a.isEmpty
        guard needsCompose, AppSettings.shared.isConfigured else { return }

        isComposing = true
        Task {
            do {
                let body = ComposeRequest(
                    partenza:  p.isEmpty ? nil : p,
                    arrivo:    a.isEmpty ? nil : a,
                    regione:   regione.isEmpty ? nil : regione,
                    kmMax:     Int(k),
                    durataMax: durataMax > 0 ? durataMax : nil
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
        partenzaSugg = []; arrivoSugg = []
        composedRoute = nil; relatedRoutes = []; composeError = nil; hasSearched = false
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
