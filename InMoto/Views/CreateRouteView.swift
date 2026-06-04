import SwiftUI
import CoreLocation

struct CreateRouteView: View {
    @EnvironmentObject var store:    RouteStore
    @EnvironmentObject var appState: AppState

    @State private var partenza      = ""
    @State private var destinazione  = ""
    @State private var partenzaSugg: [String]     = []
    @State private var destinazioneSugg: [String] = []
    @State private var result:       MotoRoute?   = nil
    @State private var isLoading     = false
    @State private var isGeolocating = false
    @State private var showFavPartenza     = false
    @State private var showFavDestinazione = false

    private var canCreate: Bool {
        !partenza.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destinazione.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func sugg(for text: String) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return store.allLocations
            .filter { $0.localizedCaseInsensitiveContains(q) }
            .prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Partenza ─────────────────────────────────────────────────
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle").foregroundStyle(.green)
                        TextField("Dove parti?", text: $partenza)
                            .autocorrectionDisabled()
                            .onChange(of: partenza) { _ in partenzaSugg = sugg(for: partenza) }
                        if isGeolocating {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            if !partenza.isEmpty {
                                Button { partenza = ""; partenzaSugg = [] } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                            Button(action: usaPosizioneAttuale) {
                                Image(systemName: "location.fill").foregroundStyle(.blue)
                            }.buttonStyle(.plain)
                            if !store.favoritePlaces.isEmpty {
                                Button { showFavPartenza = true } label: {
                                    Image(systemName: "star.fill").foregroundStyle(.orange)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    ForEach(partenzaSugg, id: \.self) { s in
                        Button {
                            partenza = s; partenzaSugg = []; hideKeyboard()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin").foregroundStyle(.green).font(.caption)
                                Text(s).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                } header: { Text("Partenza") }
                  footer: { Text("Inserisci qualsiasi luogo, anche se non è nel database") }

                // ── Destinazione ─────────────────────────────────────────────
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        TextField("Dove vuoi arrivare?", text: $destinazione)
                            .autocorrectionDisabled()
                            .onChange(of: destinazione) { _ in destinazioneSugg = sugg(for: destinazione) }
                        if !destinazione.isEmpty {
                            Button { destinazione = ""; destinazioneSugg = [] } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        if !store.favoritePlaces.isEmpty {
                            Button { showFavDestinazione = true } label: {
                                Image(systemName: "star.fill").foregroundStyle(.orange)
                            }.buttonStyle(.plain)
                        }
                    }
                    ForEach(destinazioneSugg, id: \.self) { s in
                        Button {
                            destinazione = s; destinazioneSugg = []; hideKeyboard()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin").foregroundStyle(.red).font(.caption)
                                Text(s).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                } header: { Text("Destinazione") }

                // ── Bottone ──────────────────────────────────────────────────
                Section {
                    Button(action: crea) {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView().padding(.trailing, 8) }
                            else { Image(systemName: "arrow.triangle.swap") }
                            Text(isLoading ? "Composizione…" : "Crea tragitto")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canCreate || isLoading)
                    .tint(.indigo)

                    if canCreate || result != nil {
                        Button("Azzera", role: .destructive) { reset() }
                    }
                }

                // ── Risultato ────────────────────────────────────────────────
                if let route = result {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(route.descrizione, systemImage: "map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)

                        NavigationLink(destination: RouteDetailView(route: route)) {
                            RouteCardView(route: route)
                                .padding(.horizontal, -16)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Label("Tragitto composto", systemImage: "wand.and.sparkles")
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .navigationTitle("Crea Tragitto")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showFavPartenza) {
                FavoritesPickerSheet { place in
                    partenza = place.address; partenzaSugg = []
                }
            }
            .sheet(isPresented: $showFavDestinazione) {
                FavoritesPickerSheet { place in
                    destinazione = place.address; destinazioneSugg = []
                }
            }
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private func crea() {
        hideKeyboard()
        partenzaSugg = []; destinazioneSugg = []
        isLoading = true

        let start = partenza.trimmingCharacters(in: .whitespaces)
        let end   = destinazione.trimmingCharacters(in: .whitespaces)

        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let composed = store.composeLocalRoute(da: start, a: end)
            await MainActor.run {
                result    = composed
                isLoading = false
            }
        }
    }

    private func reset() {
        partenza = ""; destinazione = ""
        partenzaSugg = []; destinazioneSugg = []
        result = nil
    }

    private func usaPosizioneAttuale() {
        isGeolocating = true
        LocationManager.shared.requestPermission()
        LocationManager.shared.start()
        Task {
            var attempts = 0
            while attempts < 20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let loc = LocationManager.shared.location {
                    let addr = await RouterService.reverseGeocode(loc)
                    await MainActor.run {
                        partenza = addr.isEmpty ? "Posizione attuale" : addr
                        partenzaSugg = []
                        isGeolocating = false
                    }
                    return
                }
                attempts += 1
            }
            await MainActor.run { isGeolocating = false }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
