import SwiftUI

struct CreateRouteView: View {
    @EnvironmentObject var store:    RouteStore
    @EnvironmentObject var appState: AppState

    @State private var partenza     = ""
    @State private var destinazione = ""
    @State private var result:      MotoRoute? = nil
    @State private var isLoading    = false
    @State private var isGeolocating = false
    @State private var showFavPartenza     = false
    @State private var showFavDestinazione = false

    @StateObject private var partenzaCompleter     = AddressCompleter()
    @StateObject private var destinazioneCompleter = AddressCompleter()

    private var canCreate: Bool {
        !partenza.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destinazione.trimmingCharacters(in: .whitespaces).isEmpty
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
                            .onChange(of: partenza) { _ in
                                partenzaCompleter.update(query: partenza)
                            }
                        if isGeolocating {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            if !partenza.isEmpty {
                                Button { partenza = ""; partenzaCompleter.clear() } label: {
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
                    ForEach(partenzaCompleter.results) { s in
                        Button {
                            partenza = s.fullText
                            partenzaCompleter.clear()
                            hideKeyboard()
                        } label: { suggestionRow(s, color: .green) }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Partenza") }
                  footer: { Text("Inserisci qualsiasi luogo o indirizzo in Italia") }

                // ── Destinazione ─────────────────────────────────────────────
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        TextField("Dove vuoi arrivare?", text: $destinazione)
                            .autocorrectionDisabled()
                            .onChange(of: destinazione) { _ in
                                destinazioneCompleter.update(query: destinazione)
                            }
                        if !destinazione.isEmpty {
                            Button { destinazione = ""; destinazioneCompleter.clear() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        if !store.favoritePlaces.isEmpty {
                            Button { showFavDestinazione = true } label: {
                                Image(systemName: "star.fill").foregroundStyle(.orange)
                            }.buttonStyle(.plain)
                        }
                    }
                    ForEach(destinazioneCompleter.results) { s in
                        Button {
                            destinazione = s.fullText
                            destinazioneCompleter.clear()
                            hideKeyboard()
                        } label: { suggestionRow(s, color: .red) }
                        .buttonStyle(.plain)
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
                            RouteCardView(route: route).padding(.horizontal, -16)
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
                    partenza = place.address
                    partenzaCompleter.clear()
                }
            }
            .sheet(isPresented: $showFavDestinazione) {
                FavoritesPickerSheet { place in
                    destinazione = place.address
                    destinazioneCompleter.clear()
                }
            }
        }
    }

    // ── Riga suggerimento ─────────────────────────────────────────────────────
    private func suggestionRow(_ s: AddressCompleter.Suggestion, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin").foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if !s.subtitle.isEmpty {
                    Text(s.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    private func crea() {
        hideKeyboard()
        partenzaCompleter.clear()
        destinazioneCompleter.clear()
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
        partenzaCompleter.clear(); destinazioneCompleter.clear()
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
                        partenzaCompleter.clear()
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
