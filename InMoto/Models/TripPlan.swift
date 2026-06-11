import Foundation

/// Un viaggio strutturato ("roadbook"): sequenza di tappe navigabili e pause,
/// con orari di marcia. Le tappe sono indipendenti — ognuna si avvia da sola
/// nel navigatore con i suoi punti di passaggio — ma vivono nello stesso viaggio.
struct TripPlan: Codable, Identifiable {
    var id: String
    var nome: String              // es. "Percorso intero V3"
    var sottotitolo: String       // es. "Carcare - Borgo San Dalmazzo"
    var totaleKm: Int             // 0 = sconosciuto
    var totaleMin: Int
    var notaFinale: String        // es. "Per tornare considera ancora: …"
    var items: [TripPlanItem]

    var tappe: [TripPlanItem] { items.filter { $0.kind == .tappa } }

    var durataFormattata: String {
        guard totaleMin > 0 else { return "" }
        let h = totaleMin / 60, m = totaleMin % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)min"
    }

    /// MotoRoute navigabile per una tappa del viaggio.
    /// L'id è stabile (viaggio + tappa): il percorso calcolato resta in cache.
    func motoRoute(for item: TripPlanItem) -> MotoRoute {
        MotoRoute(
            id: "\(id)_\(item.id)",
            nome: "\(item.titolo) — \(item.nome)",
            partenza: item.tappeNomi.first ?? "",
            arrivo: item.tappeNomi.last ?? "",
            regione: "",
            km: item.km,
            durataMin: item.durataMin,
            difficolta: "Media",
            stelle: 0,
            descrizione: item.nota.isEmpty ? "Tappa del viaggio \(nome)" : item.nota,
            tappe: item.tappeNomi,
            waypointsGmaps: item.waypointsGmaps,
            tags: ["viaggio"],
            fonte: "Roadbook",
            stagione: "Tutto l'anno",
            isCustom: true,
            legKm: nil,
            legMin: nil
        )
    }
}

struct TripPlanItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case tappa, pausa, arrivo
    }

    var id: String
    var kind: Kind
    var titolo: String            // "Tappa 1", "Pausa 2", "Arrivo"
    var nome: String              // "Autogrill Carcare - Colle della Maddalena"
    var nota: String              // testo libero (benzina, indicazioni…)
    var oraInizio: String         // "7:30" — vuota se non indicata
    var oraFine: String
    var km: Int                   // solo tappe (0 = sconosciuto)
    var durataMin: Int
    var tappeNomi: [String]       // punti di passaggio (nomi mostrati)
    var waypointsGmaps: [String]  // input per geocoding/navigazione

    var orarioFormattato: String {
        if !oraInizio.isEmpty && !oraFine.isEmpty { return "\(oraInizio) – \(oraFine)" }
        if !oraInizio.isEmpty { return oraInizio }
        return ""
    }
}
