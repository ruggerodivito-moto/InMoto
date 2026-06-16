package com.divito.inmoto.model

import kotlinx.serialization.Serializable

/**
 * Mezzo con cui si percorre il tragitto: determina il tipo di routing (OSRM
 * driving/foot) e la taratura dei tempi di percorrenza. Port di TransportMode iOS.
 */
enum class TransportMode(val id: String, val label: String, val avgSpeedKmh: Double) {
    moto("moto", "In moto", 45.0),
    piedi("piedi", "A piedi", 5.0);

    companion object {
        fun from(value: String?): TransportMode =
            entries.firstOrNull { it.id == value } ?: moto
    }
}

/** Itinerario/tragitto moto. Mappa 1:1 il MotoRoute di iOS (stessi nomi JSON). */
@Serializable
data class MotoRoute(
    val id: String,
    val nome: String,
    val partenza: String,
    val arrivo: String,
    val regione: String,
    val km: Int,
    val durataMin: Int,
    val difficolta: String,
    val stelle: Double,
    val descrizione: String,
    val tappe: List<String> = emptyList(),
    val waypointsGmaps: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val fonte: String = "",
    val stagione: String = "",
    val isCustom: Boolean? = null,
    val legKm: List<Int>? = null,   // km per ogni tratta (solo tragitti calcolati)
    val legMin: List<Int>? = null,  // minuti per ogni tratta
    val mezzo: String? = null,      // "moto" | "piedi" (null = moto, compatibilità)
) {
    /** Mezzo del tragitto (default moto se non specificato). */
    val transportMode: TransportMode get() = TransportMode.from(mezzo)

    val durataFormattata: String
        get() {
            val h = durataMin / 60
            val m = durataMin % 60
            return when {
                h == 0 -> "$m min"
                m == 0 -> "${h}h"
                else -> "${h}h ${m}min"
            }
        }

    /** "green" / "orange" / "red" — come iOS, mappato a colore nel layer UI. */
    val difficoltaColor: String
        get() = when (difficolta.lowercase()) {
            "facile" -> "green"
            "difficile" -> "red"
            else -> "orange"
        }
}

@Serializable
data class RoutesResponse(
    val ok: Boolean = false,
    val routes: List<MotoRoute> = emptyList(),
    val total: Int? = null,
    val error: String? = null,
)
