import Foundation

struct MotoRoute: Codable, Identifiable, Hashable {
    var id: String
    var nome: String
    var partenza: String
    var arrivo: String
    var regione: String
    var km: Int
    var durataMin: Int
    var difficolta: String
    var stelle: Double
    var descrizione: String
    var tappe: [String]
    var waypointsGmaps: [String]
    var tags: [String]
    var fonte: String
    var stagione: String
    var isCustom: Bool?

    enum CodingKeys: String, CodingKey {
        case id, nome, partenza, arrivo, regione, km
        case durataMin, difficolta, stelle, descrizione
        case tappe, waypointsGmaps, tags, fonte, stagione, isCustom
    }

    var durataFormattata: String {
        let h = durataMin / 60
        let m = durataMin % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)min"
    }

    var difficoltaColor: String {
        switch difficolta.lowercased() {
        case "facile":    return "green"
        case "difficile": return "red"
        default:          return "orange"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MotoRoute, rhs: MotoRoute) -> Bool { lhs.id == rhs.id }
}

struct RoutesResponse: Codable {
    var ok: Bool
    var routes: [MotoRoute]
    var total: Int?
    var error: String?
}

struct RegionsResponse: Codable {
    var ok: Bool
    var regions: [String]
    var error: String?
}

struct ComposeResponse: Codable {
    var ok: Bool
    var route: MotoRoute?
    var error: String?
}

struct ComposeRequest: Codable {
    var partenza: String?
    var arrivo: String?
    var regione: String?
    var kmMax: Int?
    var durataMax: Int?

    enum CodingKeys: String, CodingKey {
        case partenza, arrivo, regione
        case kmMax = "km_max"
        case durataMax = "durata_max"
    }
}
