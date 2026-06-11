import Foundation

/// Interpreta un roadbook testuale e lo trasforma in un TripPlan.
///
/// Formato riconosciuto (tollerante all'ordine delle righe dentro le sezioni):
///
///     NOME DEL VIAGGIO
///     Partenza - Arrivo
///     <link Google Maps percorso intero>
///     8h 10' 456Km
///
///     TAPPA 1
///     Autogrill Carcare - Colle della Maddalena
///     (nota libera, es. benzina)
///     <link Google Maps del percorso della tappa>
///     2h 15' 148Km
///     7:30 - 9:45
///
///     PAUSA 1
///     9:45 - 10:30
///     Colle della Maddalena
///     <link Google Maps del luogo>
///
///     ARRIVO
///     18:15
///     <link>
///     Borgo San Dalmazzo
///
///     PER TORNARE CONSIDERA ANCORA:
///     (testo libero → nota finale)
enum RoadbookParser {

    // MARK: - Sezione grezza

    private enum SectionKind {
        case header, tappa(Int), pausa(Int), arrivo, finale
    }

    private struct RawSection {
        let kind: SectionKind
        var lines: [String] = []
    }

    // MARK: - Parse

    /// Analizza il testo. Risolve i link abbreviati via rete (maps.app.goo.gl).
    static func parse(_ text: String) async -> TripPlan? {
        let sections = splitSections(text)
        guard sections.contains(where: { if case .tappa = $0.kind { return true }; return false }) else {
            return nil
        }

        var nome = "Viaggio"
        var sottotitolo = ""
        var totaleKm = 0
        var totaleMin = 0
        var notaFinale = ""
        var items: [TripPlanItem] = []

        for section in sections {
            let f = await interpret(section.lines)

            switch section.kind {
            case .header:
                // prima riga di testo = nome, seconda = sottotitolo
                if let first = f.textLines.first { nome = first }
                if f.textLines.count > 1 { sottotitolo = f.textLines[1] }
                totaleKm = f.km
                totaleMin = f.durataMin

            case .tappa(let n):
                var tappeNomi = f.waypoints.map { $0.displayName }
                var gwps = f.waypoints.map { geocodeInput($0) }
                // Tappa con un solo punto (link a luogo): rendila navigabile
                // partendo dalla fine della tappa precedente
                if gwps.count == 1,
                   let prev = items.last(where: { $0.kind == .tappa }),
                   let prevLastName = prev.tappeNomi.last,
                   let prevLastWp = prev.waypointsGmaps.last {
                    tappeNomi.insert(prevLastName, at: 0)
                    gwps.insert(prevLastWp, at: 0)
                }
                items.append(TripPlanItem(
                    id: "tappa\(n)",
                    kind: .tappa,
                    titolo: "Tappa \(n)",
                    nome: f.textLines.first ?? defaultName(tappeNomi),
                    nota: f.note,
                    oraInizio: f.oraInizio, oraFine: f.oraFine,
                    km: f.km, durataMin: f.durataMin,
                    tappeNomi: tappeNomi,
                    waypointsGmaps: gwps
                ))

            case .pausa(let n):
                items.append(TripPlanItem(
                    id: "pausa\(n)",
                    kind: .pausa,
                    titolo: "Pausa \(n)",
                    nome: f.textLines.first ?? f.waypoints.first?.displayName ?? "Pausa",
                    nota: f.note,
                    oraInizio: f.oraInizio, oraFine: f.oraFine,
                    km: 0, durataMin: 0,
                    tappeNomi: f.waypoints.map { $0.displayName },
                    waypointsGmaps: f.waypoints.map { geocodeInput($0) }
                ))

            case .arrivo:
                items.append(TripPlanItem(
                    id: "arrivo",
                    kind: .arrivo,
                    titolo: "Arrivo",
                    nome: f.textLines.first ?? f.waypoints.first?.displayName ?? "Arrivo",
                    nota: f.note,
                    oraInizio: f.oraInizio, oraFine: f.oraFine,
                    km: 0, durataMin: 0,
                    tappeNomi: f.waypoints.map { $0.displayName },
                    waypointsGmaps: f.waypoints.map { geocodeInput($0) }
                ))

            case .finale:
                let body = f.allText.joined(separator: "\n")
                notaFinale = notaFinale.isEmpty ? body : notaFinale + "\n" + body
            }
        }

        return TripPlan(
            id: UUID().uuidString,
            nome: nome,
            sottotitolo: sottotitolo,
            totaleKm: totaleKm,
            totaleMin: totaleMin,
            notaFinale: notaFinale,
            items: items
        )
    }

    // MARK: - Divisione in sezioni

    private static func splitSections(_ text: String) -> [RawSection] {
        var sections: [RawSection] = [RawSection(kind: .header)]

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let upper = line.uppercased()

            if let n = sectionNumber(upper, prefix: "TAPPA") {
                sections.append(RawSection(kind: .tappa(n)))
            } else if let n = sectionNumber(upper, prefix: "PAUSA") {
                sections.append(RawSection(kind: .pausa(n)))
            } else if upper.hasPrefix("ARRIVO") {
                sections.append(RawSection(kind: .arrivo))
            } else if upper.hasPrefix("PER TORNARE") || upper.hasPrefix("NOTE") {
                sections.append(RawSection(kind: .finale))
                // il resto della riga (dopo i due punti) fa parte della nota
                if let colon = line.firstIndex(of: ":") {
                    let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { sections[sections.count - 1].lines.append(rest) }
                } else {
                    sections[sections.count - 1].lines.append(line)
                }
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        return sections
    }

    private static func sectionNumber(_ upper: String, prefix: String) -> Int? {
        guard upper.hasPrefix(prefix) else { return nil }
        let rest = upper.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return Int(rest.prefix(while: { $0.isNumber })) ?? (rest.isEmpty ? 1 : nil)
    }

    // MARK: - Interpretazione delle righe di una sezione

    private struct Fields {
        var waypoints: [ParsedWaypoint] = []
        var textLines: [String] = []   // righe "nome" (testo libero non classificato)
        var note: String = ""
        var oraInizio = ""
        var oraFine = ""
        var km = 0
        var durataMin = 0
        var allText: [String] = []     // tutte le righe non-link (per la nota finale)
    }

    private static func interpret(_ lines: [String]) async -> Fields {
        var f = Fields()

        for line in lines {
            if line.lowercased().hasPrefix("http") {
                let url = GoogleMapsParser.isShortURL(line)
                    ? (await GoogleMapsParser.resolveShortURL(line) ?? line)
                    : line
                let (parsed, _) = GoogleMapsParser.parse(url)
                f.waypoints.append(contentsOf: parsed)
                continue
            }
            f.allText.append(line)

            if let (start, end) = timeRange(line) {
                if f.oraInizio.isEmpty { f.oraInizio = start; f.oraFine = end }
                continue
            }
            if let single = singleTime(line) {
                if f.oraInizio.isEmpty { f.oraInizio = single }
                continue
            }
            if line.hasPrefix("(") {
                let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                f.note = f.note.isEmpty ? cleaned : f.note + " " + cleaned
                continue
            }
            if let (km, mins) = metrics(line) {
                if km > 0 { f.km = km }
                if mins > 0 { f.durataMin = mins }
                continue
            }
            f.textLines.append(line)
        }
        return f
    }

    /// "7:30 - 9:45", "7.30-9.45" → ("7:30", "9:45")
    private static func timeRange(_ line: String) -> (String, String)? {
        let pattern = #"^(\d{1,2})[:.](\d{2})\s*[-–—]\s*(\d{1,2})[:.](\d{2})$"#
        guard let m = line.range(of: pattern, options: .regularExpression) else { return nil }
        let parts = String(line[m])
            .replacingOccurrences(of: ".", with: ":")
            .components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// "18:15" → "18:15"
    private static func singleTime(_ line: String) -> String? {
        guard line.range(of: #"^\d{1,2}[:.]\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return line.replacingOccurrences(of: ".", with: ":")
    }

    /// "2h 15' 148Km" → (148, 135) · "3h 149 Km" → (149, 180) · "101Km" → (101, 0)
    private static func metrics(_ line: String) -> (km: Int, durataMin: Int)? {
        var km = 0
        var rest = line

        // Prima i km, rimossi dalla riga: altrimenti in "3h 149 Km" il 149
        // verrebbe scambiato per i minuti della durata
        if let r = rest.range(of: #"(\d+)\s*[Kk][Mm]"#, options: .regularExpression) {
            km = Int(rest[r].prefix(while: { $0.isNumber })) ?? 0
            rest.removeSubrange(r)
        }

        var mins = 0
        if let r = rest.range(of: #"(\d+)\s*[Hh](\s*\d{1,2})?"#, options: .regularExpression) {
            let nums = String(rest[r])
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
            if let h = nums.first {
                mins = h * 60 + (nums.count > 1 ? nums[1] : 0)
            }
        }
        guard km > 0 || mins > 0 else { return nil }
        return (km, mins)
    }

    /// Stringa per il geocoding: non forzare ", Italy" sui nomi estratti
    /// dai link (i viaggi possono sconfinare, es. Francia). Le coordinate
    /// passano invariate.
    private static func geocodeInput(_ wp: ParsedWaypoint) -> String {
        if wp.gmapsWaypoint == "\(wp.displayName), Italy" {
            return wp.displayName
        }
        return wp.gmapsWaypoint
    }

    private static func defaultName(_ tappe: [String]) -> String {
        guard let first = tappe.first, let last = tappe.last, tappe.count >= 2 else {
            return tappe.first ?? "Tappa"
        }
        return "\(short(first)) - \(short(last))"
    }

    private static func short(_ s: String) -> String {
        s.components(separatedBy: ",").first ?? s
    }
}
