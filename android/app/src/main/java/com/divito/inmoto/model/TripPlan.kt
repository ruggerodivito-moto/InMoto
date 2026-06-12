package com.divito.inmoto.model

import kotlinx.serialization.Serializable

/**
 * Un viaggio strutturato ("roadbook"): sequenza di tappe navigabili e pause,
 * con orari di marcia. Le tappe sono indipendenti — ognuna si avvia da sola nel
 * navigatore con i suoi punti di passaggio — ma vivono nello stesso viaggio.
 * Port 1:1 del TripPlan di iOS.
 */
@Serializable
data class TripPlan(
    val id: String,
    var nome: String,             // es. "Percorso intero V3"
    val sottotitolo: String,      // es. "Carcare - Borgo San Dalmazzo"
    val totaleKm: Int,            // 0 = sconosciuto
    val totaleMin: Int,
    val notaFinale: String,
    val items: List<TripPlanItem>,
) {
    val tappe: List<TripPlanItem> get() = items.filter { it.kind == TripPlanItem.Kind.tappa }

    val durataFormattata: String
        get() {
            if (totaleMin <= 0) return ""
            val h = totaleMin / 60
            val m = totaleMin % 60
            return when {
                h == 0 -> "$m min"
                m == 0 -> "${h}h"
                else -> "${h}h ${m}min"
            }
        }

    /**
     * MotoRoute navigabile per una tappa del viaggio. L'id è stabile
     * (viaggio + tappa): il percorso calcolato resta in cache.
     */
    fun motoRoute(item: TripPlanItem): MotoRoute = MotoRoute(
        id = "${id}_${item.id}",
        nome = "${item.titolo} — ${item.nome}",
        partenza = item.tappeNomi.firstOrNull() ?: "",
        arrivo = item.tappeNomi.lastOrNull() ?: "",
        regione = "",
        km = item.km,
        durataMin = item.durataMin,
        difficolta = "Media",
        stelle = 0.0,
        descrizione = item.nota.ifEmpty { "Tappa del viaggio $nome" },
        tappe = item.tappeNomi,
        waypointsGmaps = item.waypointsGmaps,
        tags = listOf("viaggio"),
        fonte = "Roadbook",
        stagione = "Tutto l'anno",
        isCustom = true,
        legKm = null,
        legMin = null,
    )
}

@Serializable
data class TripPlanItem(
    val id: String,
    val kind: Kind,
    val titolo: String,            // "Tappa 1", "Pausa 2", "Arrivo"
    val nome: String,              // "Autogrill Carcare - Colle della Maddalena"
    val nota: String = "",         // testo libero (benzina, indicazioni…)
    val oraInizio: String = "",    // "7:30" — vuota se non indicata
    val oraFine: String = "",
    val km: Int = 0,               // solo tappe (0 = sconosciuto)
    val durataMin: Int = 0,
    val tappeNomi: List<String> = emptyList(),      // punti di passaggio (nomi mostrati)
    val waypointsGmaps: List<String> = emptyList(), // input per geocoding/navigazione
) {
    @Serializable
    enum class Kind { tappa, pausa, arrivo }

    val orarioFormattato: String
        get() = when {
            oraInizio.isNotEmpty() && oraFine.isNotEmpty() -> "$oraInizio – $oraFine"
            oraInizio.isNotEmpty() -> oraInizio
            else -> ""
        }
}
