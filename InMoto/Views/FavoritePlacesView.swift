import SwiftUI
import CoreLocation

// MARK: - Vista principale gestione preferiti

struct FavoritePlacesView: View {
    @EnvironmentObject var store: RouteStore
    @State private var showAdd = false
    @State private var editingPlace: FavoritePlace? = nil

    var body: some View {
        NavigationStack {
            Group {
                if store.favoritePlaces.isEmpty {
                    emptyState
                } else {
                    placesList
                }
            }
            .navigationTitle("Luoghi Preferiti")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFavoritePlaceView()
            }
            .sheet(item: $editingPlace) { place in
                EditFavoritePlaceView(place: place)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "star.circle")
                .font(.system(size: 60))
                .foregroundStyle(.orange.opacity(0.4))
            Text("Nessun luogo preferito")
                .font(.title2.weight(.semibold))
            Text("Salva i tuoi indirizzi preferiti\n(casa, lavoro, garage…)\nper usarli rapidamente nella creazione dei tragitti.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button { showAdd = true } label: {
                Label("Aggiungi luogo", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Spacer()
        }
        .padding()
    }

    private var placesList: some View {
        List {
            ForEach(store.favoritePlaces) { place in
                Button(action: { editingPlace = place }) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 42, height: 42)
                            Image(systemName: "star.fill")
                                .foregroundStyle(.orange)
                                .font(.body)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.tag)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                store.deleteFavoritePlace(at: offsets)
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
    }
}

// MARK: - Aggiungi preferito

struct AddFavoritePlaceView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var tag = ""
    @State private var address = ""
    @State private var isGeolocating = false

    private var canSave: Bool {
        !tag.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Es. Casa, Lavoro, Garage, Rifugio…", text: $tag)
                        .autocorrectionDisabled()
                } header: { Text("Etichetta") }

                Section {
                    HStack {
                        TextField("Indirizzo o nome del luogo", text: $address)
                            .autocorrectionDisabled()
                        if isGeolocating {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Button(action: usaPosizioneAttuale) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                } header: { Text("Indirizzo") }
                  footer: { Text("Puoi inserire qualsiasi luogo o indirizzo italiano") }
            }
            .navigationTitle("Nuovo preferito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva") {
                        store.saveFavoritePlace(
                            FavoritePlace(tag: tag.trimmingCharacters(in: .whitespaces),
                                          address: address.trimmingCharacters(in: .whitespaces))
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
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
                    await MainActor.run { address = addr; isGeolocating = false }
                    return
                }
                attempts += 1
            }
            await MainActor.run { isGeolocating = false }
        }
    }
}

// MARK: - Modifica preferito

struct EditFavoritePlaceView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var tag: String
    @State private var address: String
    @State private var isGeolocating = false
    private let placeId: String

    init(place: FavoritePlace) {
        self.placeId = place.id
        _tag = State(initialValue: place.tag)
        _address = State(initialValue: place.address)
    }

    private var canSave: Bool {
        !tag.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Etichetta", text: $tag)
                        .autocorrectionDisabled()
                } header: { Text("Etichetta") }

                Section {
                    HStack {
                        TextField("Indirizzo o nome del luogo", text: $address)
                            .autocorrectionDisabled()
                        if isGeolocating {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Button(action: usaPosizioneAttuale) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                } header: { Text("Indirizzo") }
            }
            .navigationTitle("Modifica preferito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva") {
                        var updated = FavoritePlace(tag: tag.trimmingCharacters(in: .whitespaces),
                                                   address: address.trimmingCharacters(in: .whitespaces))
                        // Preserve the original id via a workaround (copy struct and patch)
                        store.updateFavoritePlace(
                            FavoritePlace(id: placeId,
                                          tag: tag.trimmingCharacters(in: .whitespaces),
                                          address: address.trimmingCharacters(in: .whitespaces))
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
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
                    await MainActor.run { address = addr; isGeolocating = false }
                    return
                }
                attempts += 1
            }
            await MainActor.run { isGeolocating = false }
        }
    }
}

// MARK: - Sheet selezione preferito (picker)

struct FavoritesPickerSheet: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (FavoritePlace) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.favoritePlaces.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "star.slash").font(.system(size: 48))
                            .foregroundStyle(.orange.opacity(0.4))
                        Text("Nessun luogo preferito").font(.headline)
                        Text("Aggiungili dalla scheda Preferiti in basso")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(store.favoritePlaces) { place in
                        Button(action: { onSelect(place); dismiss() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.tag).font(.subheadline.weight(.semibold))
                                    Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scegli preferito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }
}

// Estensione per FavoritePlace con id esterno (per EditFavoritePlaceView)
extension FavoritePlace {
    init(id: String, tag: String, address: String) {
        self.id = id
        self.tag = tag
        self.address = address
    }
}
