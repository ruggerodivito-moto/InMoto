package com.divito.inmoto.data

import com.divito.inmoto.model.TripPlan
import com.divito.inmoto.model.TripPlanItem
import java.util.UUID

/**
 * Interpreta un roadbook testuale e lo trasforma in un TripPlan.
 * Port 1:1 del RoadbookParser di iOS. Vedi il formato nel commento originale:
 * sezioni TAPPA n / PAUSA n / ARRIVO / PER TORNARE, orari "7:30 - 9:45",
 * metriche "2h 15' 148Km", note tra parentesi, link Google Maps.
 */
object RoadbookParser {

    // MARK: - Sezione grezza
    private sealed interface SectionKind {
        data object Header : SectionKind
        data class Tappa(val n: Int) : SectionKind
        data class Pausa(val n: Int) : SectionKind
        data object Arrivo : SectionKind
        data object Finale : SectionKind
    }

    private class RawSection(val kind: SectionKind) {
        val lines = mutableListOf<String>()
    }

    // MARK: - Parse

    /** Analizza il testo. Risolve i link abbreviati via rete (maps.app.goo.gl). */
    suspend fun parse(text: String): TripPlan? {
        val sections = splitSections(text)
        if (sections.none { it.kind is SectionKind.Tappa }) return null

        var nome = "Viaggio"
        var sottotitolo = ""
        var totaleKm = 0
        var totaleMin = 0
        var notaFinale = ""
        val items = mutableListOf<TripPlanItem>()

        for (section in sections) {
            val f = interpret(section.lines)

            when (val kind = section.kind) {
                is SectionKind.Header -> {
                    f.textLines.firstOrNull()?.let { nome = it }
                    if (f.textLines.size > 1) sottotitolo = f.textLines[1]
                    totaleKm = f.km
                    totaleMin = f.durataMin
                }

                is SectionKind.Tappa -> {
                    val nameLine = f.textLines.firstOrNull()
                    val tappeNomi = f.waypoints.map { it.displayName }.toMutableList()
                    val gwps = f.waypoints.map { geocodeInput(it) }.toMutableList()
                    // Tappa con un solo punto: ricava la partenza dalla tappa
                    // precedente, oppure dal nome "Partenza - Arrivo".
                    if (gwps.size == 1) {
                        val prev = items.lastOrNull { it.kind == TripPlanItem.Kind.tappa }
                        val prevLastName = prev?.tappeNomi?.lastOrNull()
                        val prevLastWp = prev?.waypointsGmaps?.lastOrNull()
                        if (prevLastName != null && prevLastWp != null) {
                            tappeNomi.add(0, prevLastName)
                            gwps.add(0, prevLastWp)
                        } else {
                            endpointsFromName(nameLine)?.let { (start, _) ->
                                tappeNomi.add(0, start)
                                gwps.add(0, start)
                            }
                        }
                    } else if (gwps.isEmpty()) {
                        endpointsFromName(nameLine)?.let { (start, end) ->
                            tappeNomi.clear(); tappeNomi.add(start); tappeNomi.add(end)
                            gwps.clear(); gwps.add(start); gwps.add(end)
                        }
                    }
                    items.add(
                        TripPlanItem(
                            id = "tappa${kind.n}",
                            kind = TripPlanItem.Kind.tappa,
                            titolo = "Tappa ${kind.n}",
                            nome = nameLine ?: defaultName(tappeNomi),
                            nota = f.note,
                            oraInizio = f.oraInizio, oraFine = f.oraFine,
                            km = f.km, durataMin = f.durataMin,
                            tappeNomi = tappeNomi,
                            waypointsGmaps = gwps,
                        )
                    )
                }

                is SectionKind.Pausa -> items.add(
                    TripPlanItem(
                        id = "pausa${kind.n}",
                        kind = TripPlanItem.Kind.pausa,
                        titolo = "Pausa ${kind.n}",
                        nome = f.textLines.firstOrNull() ?: f.waypoints.firstOrNull()?.displayName ?: "Pausa",
                        nota = f.note,
                        oraInizio = f.oraInizio, oraFine = f.oraFine,
                        km = 0, durataMin = 0,
                        tappeNomi = f.waypoints.map { it.displayName },
                        waypointsGmaps = f.waypoints.map { geocodeInput(it) },
                    )
                )

                is SectionKind.Arrivo -> items.add(
                    TripPlanItem(
                        id = "arrivo",
                        kind = TripPlanItem.Kind.arrivo,
                        titolo = "Arrivo",
                        nome = f.textLines.firstOrNull() ?: f.waypoints.firstOrNull()?.displayName ?: "Arrivo",
                        nota = f.note,
                        oraInizio = f.oraInizio, oraFine = f.oraFine,
                        km = 0, durataMin = 0,
                        tappeNomi = f.waypoints.map { it.displayName },
                        waypointsGmaps = f.waypoints.map { geocodeInput(it) },
                    )
                )

                is SectionKind.Finale -> {
                    val body = f.allText.joinToString("\n")
                    notaFinale = if (notaFinale.isEmpty()) body else "$notaFinale\n$body"
                }
            }
        }

        return TripPlan(
            id = UUID.randomUUID().toString(),
            nome = nome,
            sottotitolo = sottotitolo,
            totaleKm = totaleKm,
            totaleMin = totaleMin,
            notaFinale = notaFinale,
            items = items,
        )
    }

    // MARK: - Divisione in sezioni

    private fun splitSections(text: String): List<RawSection> {
        val sections = mutableListOf(RawSection(SectionKind.Header))

        for (raw in text.split(Regex("\\r?\\n"))) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val upper = line.uppercase()

            val tappaN = sectionNumber(upper, "TAPPA")
            val pausaN = sectionNumber(upper, "PAUSA")
            when {
                tappaN != null -> sections.add(RawSection(SectionKind.Tappa(tappaN)))
                pausaN != null -> sections.add(RawSection(SectionKind.Pausa(pausaN)))
                upper.startsWith("ARRIVO") -> sections.add(RawSection(SectionKind.Arrivo))
                upper.startsWith("PER TORNARE") || upper.startsWith("NOTE") -> {
                    sections.add(RawSection(SectionKind.Finale))
                    val colon = line.indexOf(':')
                    if (colon >= 0) {
                        val rest = line.substring(colon + 1).trim()
                        if (rest.isNotEmpty()) sections.last().lines.add(rest)
                    } else {
                        sections.last().lines.add(line)
                    }
                }
                else -> sections.last().lines.add(line)
            }
        }
        return sections
    }

    private fun sectionNumber(upper: String, prefix: String): Int? {
        if (!upper.startsWith(prefix)) return null
        val rest = upper.drop(prefix.length).trim()
        val digits = rest.takeWhile { it.isDigit() }
        return digits.toIntOrNull() ?: if (rest.isEmpty()) 1 else null
    }

    // MARK: - Interpretazione delle righe di una sezione

    private class Fields {
        val waypoints = mutableListOf<ParsedWaypoint>()
        val textLines = mutableListOf<String>()
        var note = ""
        var oraInizio = ""
        var oraFine = ""
        var km = 0
        var durataMin = 0
        val allText = mutableListOf<String>()
    }

    private suspend fun interpret(lines: List<String>): Fields {
        val f = Fields()
        for (line in lines) {
            if (line.lowercase().startsWith("http")) {
                val url = if (GoogleMapsParser.isShortURL(line))
                    (GoogleMapsParser.resolveShortURL(line) ?: line) else line
                val (parsed, _) = GoogleMapsParser.parse(url)
                f.waypoints.addAll(parsed)
                continue
            }
            f.allText.add(line)

            val range = timeRange(line)
            if (range != null) {
                if (f.oraInizio.isEmpty()) { f.oraInizio = range.first; f.oraFine = range.second }
                continue
            }
            val single = singleTime(line)
            if (single != null) {
                if (f.oraInizio.isEmpty()) f.oraInizio = single
                continue
            }
            if (line.startsWith("(")) {
                val cleaned = line.trim('(', ')')
                f.note = if (f.note.isEmpty()) cleaned else "${f.note} $cleaned"
                continue
            }
            val m = metrics(line)
            if (m != null) {
                if (m.first > 0) f.km = m.first
                if (m.second > 0) f.durataMin = m.second
                continue
            }
            f.textLines.add(line)
        }
        return f
    }

    private val timeRangeRegex = Regex("""^(\d{1,2})[:.](\d{2})\s*[-–—]\s*(\d{1,2})[:.](\d{2})$""")
    private val singleTimeRegex = Regex("""^\d{1,2}[:.]\d{2}$""")
    private val kmRegex = Regex("""(\d+)\s*[Kk][Mm]""")
    private val hourRegex = Regex("""(\d+)\s*[Hh](\s*\d{1,2})?""")

    /** "7:30 - 9:45", "7.30-9.45" → ("7:30", "9:45") */
    private fun timeRange(line: String): Pair<String, String>? {
        if (!timeRangeRegex.matches(line)) return null
        val parts = line.replace(".", ":")
            .split(Regex("[-–—]"))
            .map { it.trim() }
        if (parts.size != 2) return null
        return parts[0] to parts[1]
    }

    /** "18:15" → "18:15" */
    private fun singleTime(line: String): String? {
        if (!singleTimeRegex.matches(line)) return null
        return line.replace(".", ":")
    }

    /** "2h 15' 148Km" → (148, 135) · "3h 149 Km" → (149, 180) · "101Km" → (101, 0) */
    private fun metrics(line: String): Pair<Int, Int>? {
        var km = 0
        var rest = line
        kmRegex.find(rest)?.let { m ->
            km = m.value.takeWhile { it.isDigit() }.toIntOrNull()
                ?: m.groupValues[1].toIntOrNull() ?: 0
            rest = rest.removeRange(m.range)
        }
        var mins = 0
        hourRegex.find(rest)?.let { m ->
            val nums = m.value.split(Regex("\\D+")).filter { it.isNotEmpty() }.mapNotNull { it.toIntOrNull() }
            nums.firstOrNull()?.let { h ->
                mins = h * 60 + (if (nums.size > 1) nums[1] else 0)
            }
        }
        if (km <= 0 && mins <= 0) return null
        return km to mins
    }

    /** Non forzare ", Italy" sui nomi estratti dai link (i viaggi sconfinano). */
    private fun geocodeInput(wp: ParsedWaypoint): String =
        if (wp.gmapsWaypoint == "${wp.displayName}, Italy") wp.displayName else wp.gmapsWaypoint

    private val dashRegex = Regex("""\s+[–—]\s+""")

    /** Da "Autogrill Carcare - Colle della Maddalena" ricava (partenza, arrivo). */
    private fun endpointsFromName(name: String?): Pair<String, String>? {
        val raw = name?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val parts = raw.replace(dashRegex, " - ")
            .split(" - ")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (parts.size < 2) return null
        return parts.first() to parts.last()
    }

    /** True se la riga è un metadato (orario/metriche/intestazione), non un luogo. */
    fun isNonPlaceLine(raw: String): Boolean {
        val line = raw.trim()
        if (line.isEmpty()) return true
        val upper = line.uppercase()
        for (h in listOf("TAPPA", "PAUSA", "ARRIVO", "PARTENZA", "PER TORNARE", "NOTE")) {
            if (upper == h || upper.startsWith("$h ")) return true
        }
        if (timeRange(line) != null) return true
        if (singleTime(line) != null) return true
        if (metrics(line) != null) return true
        return false
    }

    private fun defaultName(tappe: List<String>): String {
        val first = tappe.firstOrNull()
        val last = tappe.lastOrNull()
        if (first == null || last == null || tappe.size < 2) return first ?: "Tappa"
        return "${short(first)} - ${short(last)}"
    }

    private fun short(s: String): String = s.split(",").firstOrNull() ?: s
}
