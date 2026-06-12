import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: RouteStore
    @State private var selectedRegion: String? = nil
    @State private var showRegionPicker = false

    var displayedRoutes: [MotoRoute] {
        guard let reg = selectedRegion else { return [] }
        return store.routes.filter { $0.regione.localizedCaseInsensitiveCompare(reg) == .orderedSame }
            .sorted { $0.stelle > $1.stelle }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Region picker bar
            regionBar

                if selectedRegion == nil {
                    emptyRegionPrompt
                } else if displayedRoutes.isEmpty {
                    ContentUnavailableView("Nessun itinerario",
                        systemImage: "map.circle",
                        description: Text("Nessun percorso trovato per \(selectedRegion ?? "")"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            HStack {
                                Text("\(displayedRoutes.count) itinerari · ordinati per valutazione")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            ForEach(displayedRoutes) { route in
                                NavigationLink(destination: RouteDetailView(route: route)) {
                                    RouteCardView(route: route)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        .navigationTitle("Viaggi Personali")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                syncButton
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            RegionPickerSheet(selected: $selectedRegion)
        }
    }

    // ── Barra selezione regione ─────────────────────────────────────────────
    private var regionBar: some View {
        Button(action: { showRegionPicker = true }) {
            HStack {
                Image(systemName: "map")
                    .foregroundStyle(.indigo)
                Text(selectedRegion ?? "Scegli una regione…")
                    .foregroundStyle(selectedRegion == nil ? .secondary : .primary)
                    .fontWeight(selectedRegion != nil ? .semibold : .regular)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(.separator)), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    // ── Prompt iniziale ─────────────────────────────────────────────────────
    private var emptyRegionPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "motorcycle")
                .font(.system(size: 60))
                .foregroundStyle(.indigo.opacity(0.4))
            Text("Scegli una regione")
                .font(.title2.weight(.semibold))
            Text("Seleziona la regione in alto per scoprire\ni migliori itinerari moto.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Button("Scegli regione") { showRegionPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            Spacer()
        }
        .padding()
    }

    // ── Sync button ─────────────────────────────────────────────────────────
    private var syncButton: some View {
        Group {
            if store.isLoading {
                ProgressView()
            } else {
                Button(action: { Task { await store.syncFromServer() } }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

// ── Sheet selezione regione ──────────────────────────────────────────────────
struct RegionPickerSheet: View {
    @EnvironmentObject var store: RouteStore
    @Binding var selected: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if selected != nil {
                    Button(role: .destructive) {
                        selected = nil
                        dismiss()
                    } label: {
                        Label("Rimuovi selezione", systemImage: "xmark.circle")
                    }
                }
                ForEach(store.regions, id: \.self) { region in
                    Button {
                        selected = region
                        dismiss()
                    } label: {
                        HStack {
                            Text(region)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected == region {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Seleziona Regione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
