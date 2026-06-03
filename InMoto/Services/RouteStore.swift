import Foundation
import Combine

@MainActor
class RouteStore: ObservableObject {
    @Published var routes: [MotoRoute] = []
    @Published var regions: [String] = []
    @Published var isLoading = false
    @Published var syncMessage: String?
    @Published var lastSyncDate: Date?

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("routes_cache.json")
    }()

    private let syncDateKey = "lastSyncDate"

    // ── Caricamento iniziale ────────────────────────────────────────────────
    func loadInitial() {
        // Prima prova dalla cache (più aggiornata)
        if loadFromCache() { return }
        // Poi dal bundle JSON
        loadFromBundle()
    }

    private func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "routes", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([MotoRoute].self, from: data)
            routes = loaded
            updateRegions()
        } catch {
            print("Bundle load error: \(error)")
        }
    }

    private func loadFromCache() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return false }
        do {
            let data = try Data(contentsOf: cacheURL)
            let loaded = try JSONDecoder().decode([MotoRoute].self, from: data)
            routes = loaded
            updateRegions()
            lastSyncDate = UserDefaults.standard.object(forKey: syncDateKey) as? Date
            return true
        } catch {
            return false
        }
    }

    private func saveToCache(_ newRoutes: [MotoRoute]) {
        do {
            let data = try JSONEncoder().encode(newRoutes)
            try data.write(to: cacheURL, options: .atomic)
            let now = Date()
            UserDefaults.standard.set(now, forKey: syncDateKey)
            lastSyncDate = now
        } catch {
            print("Cache save error: \(error)")
        }
    }

    private func updateRegions() {
        var seen = Set<String>()
        regions = routes.compactMap { r -> String? in
            guard !r.regione.isEmpty, !seen.contains(r.regione) else { return nil }
            seen.insert(r.regione)
            return r.regione
        }.sorted()
    }

    // ── Sync dal server ─────────────────────────────────────────────────────
    func syncFromServer() async {
        let settings = AppSettings.shared
        guard settings.isConfigured else {
            syncMessage = "Configura l'URL del server nelle Impostazioni"
            return
        }
        isLoading = true
        syncMessage = "Sincronizzazione in corso…"
        do {
            let url = settings.apiURL("/api/mobile/moto/routes")
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.setValue(settings.apiKey, forHTTPHeaderField: "X-Moto-Key")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                syncMessage = "Errore server (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                isLoading = false
                return
            }
            let result = try JSONDecoder().decode(RoutesResponse.self, from: data)
            if result.ok {
                routes = result.routes
                updateRegions()
                saveToCache(result.routes)
                syncMessage = "\(result.routes.count) itinerari aggiornati"
            } else {
                syncMessage = result.error ?? "Errore sconosciuto"
            }
        } catch {
            syncMessage = "Errore: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // ── Filtro locale ───────────────────────────────────────────────────────
    func filtered(regione: String?, partenza: String?, arrivo: String?,
                  kmMax: Int?, durataMax: Int?) -> [MotoRoute] {
        routes.filter { r in
            if let reg = regione, !reg.isEmpty,
               r.regione.localizedCaseInsensitiveCompare(reg) != .orderedSame { return false }
            if let p = partenza, !p.isEmpty,
               !r.partenza.localizedCaseInsensitiveContains(p) { return false }
            if let a = arrivo, !a.isEmpty,
               !r.arrivo.localizedCaseInsensitiveContains(a) { return false }
            if let k = kmMax, r.km > k { return false }
            if let d = durataMax, r.durataMin > d { return false }
            return true
        }.sorted { $0.stelle > $1.stelle }
    }
}
