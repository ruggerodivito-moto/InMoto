import SwiftUI
import UniformTypeIdentifiers

/// Importa una traccia .gpx dal file system (app File): la traccia viene seguita
/// esattamente, senza ricalcolo stradale. Vedi `GPXImporter`.
struct GPXImportView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var track: GPXImporter.ParsedTrack?
    @State private var preview: MotoRoute?
    @State private var name = ""
    @State private var errorMsg: String?
    @State private var localFiles: [URL] = []

    /// Tipi accettati: il sistema spesso non conosce l'estensione .gpx, quindi
    /// si includono anche XML e dati generici così il file resta selezionabile.
    private static let gpxTypes: [UTType] = {
        var types: [UTType] = []
        if let gpx = UTType(filenameExtension: "gpx") { types.append(gpx) }
        types.append(.xml)
        types.append(.data)
        return types
    }()

    var body: some View {
        NavigationStack {
            Form {
                introSection
                if !localFiles.isEmpty { localFilesSection }
                if let t = track {
                    nameSection
                    if let r = preview { previewSection(r, pointCount: t.points.count) }
                }
                if let e = errorMsg { errorSection(e) }
            }
            .navigationTitle("Importa traccia GPX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: Self.gpxTypes,
                          allowsMultipleSelection: false,
                          onCompletion: handlePick)
            .onAppear(perform: scanLocalFiles)
        }
    }

    // ── Sezioni ────────────────────────────────────────────────────────────────
    private var introSection: some View {
        Section {
            Button { showPicker = true } label: {
                Label(track == nil ? "Scegli file GPX…" : "Scegli un altro file",
                      systemImage: "doc.badge.plus")
            }
            Text("Importa una traccia .gpx (Garmin, Strava, Komoot…). InMoto seguirà esattamente il tracciato registrato, senza ricalcolarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// File .gpx già presenti nella cartella Documenti dell'app (es. copiati via
    /// USB/Finder o salvati "in InMoto" da un'altra app).
    private var localFilesSection: some View {
        Section("File GPX nell'app") {
            ForEach(localFiles, id: \.self) { url in
                Button {
                    loadGPX(from: url, scoped: false)
                } label: {
                    Label(url.lastPathComponent, systemImage: "doc.text")
                }
            }
        }
    }

    private var nameSection: some View {
        Section("Nome del tragitto") {
            TextField("Nome", text: $name)
                .autocorrectionDisabled()
        }
    }

    private func previewSection(_ r: MotoRoute, pointCount: Int) -> some View {
        Section {
            HStack {
                Label("\(r.km) km", systemImage: "road.lanes")
                Spacer()
                Label("~\(r.durataFormattata)", systemImage: "clock")
            }
            .font(.subheadline)
            HStack {
                Label("\(pointCount) punti", systemImage: "scribble")
                Spacer()
                Label("\(r.tappe.count) tappe", systemImage: "flag.checkered")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button(action: salva) {
                HStack {
                    Spacer()
                    Image(systemName: "bookmark.fill")
                    Text("Salva tragitto").fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } header: {
            Label("Traccia pronta", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func errorSection(_ e: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(e)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    // ── Logica ─────────────────────────────────────────────────────────────────

    /// Elenca i .gpx nella cartella Documenti dell'app
    private func scanLocalFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let found = (try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: nil)) ?? []
        localFiles = found
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        errorMsg = nil
        switch result {
        case .failure(let err):
            errorMsg = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            loadGPX(from: url, scoped: true)
        }
    }

    /// Legge e analizza un file GPX. `scoped` per gli URL del selettore (file
    /// fuori dal sandbox, serve il security-scoped access); falso per i file già
    /// nella cartella Documenti dell'app.
    private func loadGPX(from url: URL, scoped: Bool) {
        errorMsg = nil
        let access = scoped && url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let fallback = url.deletingPathExtension().lastPathComponent
            let parsed = try GPXImporter.parse(data: data, fallbackName: fallback)
            let built = GPXImporter.buildRoute(from: parsed, displayName: parsed.name)
            track = parsed
            name = parsed.name
            preview = built.route
        } catch {
            track = nil
            preview = nil
            errorMsg = error.localizedDescription
        }
    }

    private func salva() {
        guard let parsed = track else { return }
        // Ricostruisce col nome eventualmente modificato e mette in cache la
        // NavigationRoute "esatta" (routeId condiviso col MotoRoute salvato).
        let built = GPXImporter.buildRoute(from: parsed, displayName: name)
        RouterService.shared.cacheRoute(built.navRoute)
        store.savePersonalRoute(built.route)
        dismiss()
    }
}
