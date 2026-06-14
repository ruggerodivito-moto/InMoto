package com.divito.inmoto.data

import java.net.URLDecoder

/** Waypoint estratto dal parsing (link o testo libero). Port di ParsedWaypoint iOS. */
data class ParsedWaypoint(
    val displayName: String,   // testo mostrato all'utente
    val gmapsWaypoint: String, // stringa usata per geocoding (coord o nome)
    val source: String?,       // "Google Maps percorso", "DB", null = testo libero
)

/** Parser URL Google Maps. Port 1:1 di GoogleMapsParser iOS. */
object GoogleMapsParser {

    /** Riconosce URL abbreviati che richiedono risoluzione HTTP. */
    fun isShortURL(urlString: String): Boolean {
        val s = urlString.lowercase()
        return s.contains("goo.gl") || s.contains("maps.app") || s.contains("g.co/maps")
    }

    /** Segue il redirect e restituisce l'URL finale (es. google.com/maps/place/…). */
    suspend fun resolveShortURL(urlString: String): String? =
        Http.resolveFinalUrl(urlString)

    /** Restituisce (waypoints estratti, eventuale messaggio di warning). */
    fun parse(urlString: String): Pair<List<ParsedWaypoint>, String?> {
        val path = runCatching { java.net.URL(urlString).path }.getOrNull()
            ?: return emptyList<ParsedWaypoint>() to "URL non valido"

        // ── Percorso con tappe: /maps/dir/A/B/C/ ───────────────────────────
        if (path.contains("/dir/")) {
            // Le coordinate esatte dei waypoint sono nel parametro data=
            // (coppie !2m2!1d<lon>!2d<lat>). Hanno la PRIORITÀ sui nomi: così
            // si segue esattamente il tracciato Google senza geocoding a
            // indovinare (i nomi verbosi tipo "Autogrill, A6…" o le tappe in
            // Francia non sempre si geocodificano). I nomi restano l'etichetta.
            val coords = extractDirCoordinates(urlString)
            val stops = extractDirStops(path)
            if (coords.isNotEmpty()) {
                val wps = coords.mapIndexed { i, c ->
                    val name = stops.getOrNull(i) ?: c
                    ParsedWaypoint(name, c, "Google Maps percorso")
                }
                return wps to null
            }
            if (stops.isNotEmpty()) {
                val wps = stops.map {
                    ParsedWaypoint(it, "$it, Italy", "Google Maps percorso")
                }
                return wps to null
            }
        }

        // ── Luogo singolo: /maps/place/Name/@lat,lon ───────────────────────
        if (path.contains("/place/")) {
            extractCoordinates(urlString)?.let { coord ->
                val name = extractPlaceName(path) ?: coord
                return listOf(ParsedWaypoint(name, coord, "Google Maps luogo")) to null
            }
            extractPlaceName(path)?.let { name ->
                return listOf(ParsedWaypoint(name, "$name, Italy", "Google Maps luogo")) to null
            }
        }

        // ── Ricerca generica con coordinate ────────────────────────────────
        extractCoordinates(urlString)?.let { coord ->
            return listOf(ParsedWaypoint(coord, coord, "Coordinate")) to null
        }

        return emptyList<ParsedWaypoint>() to null
    }

    // Estrae tappe da /dir/Partenza/Tappa1/Tappa2/Arrivo/
    private fun extractDirStops(path: String): List<String> {
        val idx = path.indexOf("/dir/")
        if (idx < 0) return emptyList()
        val after = path.substring(idx + "/dir/".length)
        return after.split("/").mapNotNull { seg ->
            val decoded = runCatching {
                URLDecoder.decode(seg, "UTF-8")
            }.getOrDefault(seg).replace("+", " ")
            val clean = decoded.trim()
            if (clean.isEmpty() || clean.startsWith("@") ||
                clean.startsWith("data=") || clean.contains("=")
            ) null else clean
        }
    }

    // Coppie coordinate dei waypoint in un link /dir/: !2m2!1d<lon>!2d<lat>.
    // Restituisce stringhe "lat,lon" nell'ordine delle tappe.
    private val dirCoordRegex = Regex("""!2m2!1d(-?[0-9.]+)!2d(-?[0-9.]+)""")
    private fun extractDirCoordinates(urlString: String): List<String> =
        dirCoordRegex.findAll(urlString).mapNotNull { m ->
            val lon = m.groupValues[1].toDoubleOrNull()
            val lat = m.groupValues[2].toDoubleOrNull()
            if (lat != null && lon != null && lat in -90.0..90.0 && lon in -180.0..180.0)
                "$lat,$lon" else null
        }.toList()

    // Estrae nome luogo da /place/Nome+Luogo/
    private fun extractPlaceName(path: String): String? {
        val idx = path.indexOf("/place/")
        if (idx < 0) return null
        val after = path.substring(idx + "/place/".length)
        val first = after.split("/").firstOrNull() ?: return null
        val decoded = runCatching {
            URLDecoder.decode(first, "UTF-8")
        }.getOrDefault(first).replace("+", " ").trim()
        return decoded.ifEmpty { null }
    }

    // Estrae @lat,lon dall'URL
    private fun extractCoordinates(urlString: String): String? {
        val idx = urlString.indexOf("@")
        if (idx < 0) return null
        val after = urlString.substring(idx + 1)
        val parts = after.split(",")
        if (parts.size < 2) return null
        val lat = parts[0].toDoubleOrNull() ?: return null
        val lon = parts[1].toDoubleOrNull() ?: return null
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
        return "$lat,$lon"
    }
}
