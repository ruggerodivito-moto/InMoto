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

    // ── Composizione tragitto locale ────────────────────────────────────────
    func composeLocalRoute(da startText: String, a endText: String) -> MotoRoute {
        func fuzzy(_ a: String, _ b: String) -> Bool {
            let a = a.lowercased(), b = b.lowercased()
            return a.contains(b) || b.contains(a)
        }

        // Candidati per partenza e arrivo
        let startCandidates = routes.filter { fuzzy($0.partenza, startText) }
                                    .sorted { $0.stelle > $1.stelle }
        let endCandidates   = routes.filter { fuzzy($0.arrivo, endText) }
                                    .sorted { $0.stelle > $1.stelle }

        // Fase 1 — unico route che copre entrambi
        if let direct = routes.first(where: { fuzzy($0.partenza, startText) && fuzzy($0.arrivo, endText) }) {
            return direct
        }

        // Fase 2 — catena diretta: route1.arrivo ≈ route2.partenza
        for s in startCandidates.prefix(8) {
            for e in endCandidates.prefix(8) {
                guard s.id != e.id else { continue }
                if fuzzy(s.arrivo, e.partenza) {
                    return buildComposed([s, e], start: startText, end: endText)
                }
            }
        }

        // Fase 3 — catena con un bridge (tre tappe)
        for s in startCandidates.prefix(5) {
            for e in endCandidates.prefix(5) {
                guard s.id != e.id else { continue }
                for bridge in routes {
                    guard bridge.id != s.id && bridge.id != e.id else { continue }
                    if fuzzy(bridge.partenza, s.arrivo) && fuzzy(bridge.arrivo, e.partenza) {
                        return buildComposed([s, bridge, e], start: startText, end: endText)
                    }
                }
            }
        }

        // Fase 4 — fallback: miglior partenza + miglior arrivo (anche non connesse)
        var legs: [MotoRoute] = []
        if let s = startCandidates.first { legs.append(s) }
        if let e = endCandidates.first, e.id != legs.first?.id { legs.append(e) }

        // Fase 5 — nulla trovato: top route per stelle
        if legs.isEmpty {
            legs = Array(routes.sorted { $0.stelle > $1.stelle }.prefix(2))
        }

        return buildComposed(legs, start: startText, end: endText)
    }

    private func buildComposed(_ legs: [MotoRoute], start: String, end: String) -> MotoRoute {
        let totalKm  = legs.reduce(0) { $0 + $1.km }
        let totalMin = legs.reduce(0) { $0 + $1.durataMin }
        let avgStelle = legs.isEmpty ? 4.0 : legs.reduce(0.0) { $0 + $1.stelle } / Double(legs.count)
        let legNames  = legs.map { $0.nome }.joined(separator: " → ")
        let regioni   = Array(Set(legs.map { $0.regione })).sorted().joined(separator: ", ")
        let n = legs.count
        return MotoRoute(
            id: UUID().uuidString,
            nome: "Da \(start) a \(end)",
            partenza: start,
            arrivo: end,
            regione: regioni,
            km: totalKm,
            durataMin: totalMin,
            difficolta: "Media",
            stelle: avgStelle,
            descrizione: "Tragitto in \(n) tapp\(n == 1 ? "a" : "e"): \(legNames)",
            tappe: legs.flatMap { $0.tappe },
            waypointsGmaps: legs.flatMap { $0.waypointsGmaps },
            tags: Array(Set(legs.flatMap { $0.tags })).sorted(),
            fonte: "Composto InMoto",
            stagione: legs.first?.stagione ?? "Tutto l'anno",
            isCustom: true
        )
    }

    // ── Luoghi unici (per autocomplete) ────────────────────────────────────
    var allLocations: [String] {
        var seen = Set<String>()
        for r in routes {
            let p = r.partenza.trimmingCharacters(in: .whitespaces)
            let a = r.arrivo.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty { seen.insert(p) }
            if !a.isEmpty { seen.insert(a) }
        }
        return seen.sorted()
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
