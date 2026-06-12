package com.divito.inmoto.data

import android.content.Context
import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.GeocodedWaypoint
import com.divito.inmoto.model.NavigationRoute
import com.divito.inmoto.model.RouteLeg
import com.divito.inmoto.model.RouteStep
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.URLEncoder
import kotlin.math.abs

/**
 * Geocoding (Nominatim/OSM) + routing (OSRM pubblico) + cache.
 * Port del RouterService iOS: MKDirections → OSRM, CLGeocoder → Nominatim.
 */
object RouterService {

    private const val OSRM_BASE = "https://router.project-osrm.org/route/v1/driving"
    private const val NOMINATIM = "https://nominatim.openstreetmap.org/search"

    class RouterException(message: String) : Exception(message)

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    // MARK: - Geocoding pubblico

    suspend fun geocodeWaypointsMixed(inputs: List<String>): List<GeocodedWaypoint> {
        if (inputs.isEmpty()) throw RouterException("Nessuna tappa definita nel percorso")
        val result = mutableListOf<GeocodedWaypoint>()
        for ((i, input) in inputs.withIndex()) {
            result.add(geocodeMixed(input))
            if (i < inputs.size - 1) delay(900) // rispetta il rate-limit Nominatim
        }
        return result
    }

    private suspend fun geocodeMixed(input: String): GeocodedWaypoint {
        val t = input.trim()
        // Formato "lat,lon" (da link Google Maps)
        val parts = t.split(",")
        if (parts.size == 2) {
            val lat = parts[0].trim().toDoubleOrNull()
            val lon = parts[1].trim().toDoubleOrNull()
            if (lat != null && lon != null && abs(lat) <= 90 && abs(lon) <= 180) {
                return GeocodedWaypoint(name = t, latitude = lat, longitude = lon)
            }
        }
        return geocodeOne(t)
    }

    private suspend fun geocodeOne(address: String): GeocodedWaypoint {
        val q = URLEncoder.encode(address, "UTF-8")
        val url = "$NOMINATIM?q=$q&format=json&limit=1"
        val resp = runCatching {
            Http.get(url, headers = mapOf("Accept-Language" to "it"))
        }.getOrNull()
        if (resp == null || resp.status != 200) throw RouterException("Impossibile localizzare: $address")
        val arr = runCatching { json.parseToJsonElement(resp.body).jsonArray }.getOrNull()
        val first = arr?.firstOrNull()?.jsonObject ?: throw RouterException("Impossibile localizzare: $address")
        val lat = first["lat"]?.jsonPrimitive?.content?.toDoubleOrNull()
        val lon = first["lon"]?.jsonPrimitive?.content?.toDoubleOrNull()
            ?: throw RouterException("Impossibile localizzare: $address")
        if (lat == null) throw RouterException("Impossibile localizzare: $address")
        return GeocodedWaypoint(name = address, latitude = lat, longitude = lon)
    }

    // MARK: - Routing pubblico

    suspend fun computeLegs(context: Context, waypoints: List<GeocodedWaypoint>): List<RouteLeg> {
        val legs = mutableListOf<RouteLeg>()
        for (i in 0 until waypoints.size - 1) {
            val from = waypoints[i]; val to = waypoints[i + 1]
            cachedLeg(context, from, to)?.let { legs.add(it); continue }
            val leg = directionsLeg(from.name, from.point, to.name, to.point)
            storeLeg(context, leg, from, to)
            legs.add(leg)
        }
        return legs
    }

    /** Tratta di collegamento dalla posizione attuale a una tappa (non cacheata). */
    suspend fun connectorLeg(from: GeoPoint, to: GeocodedWaypoint): RouteLeg =
        directionsLeg("Posizione attuale", from, to.name, to.point)

    private suspend fun directionsLeg(
        fromName: String, from: GeoPoint, toName: String, to: GeoPoint,
    ): RouteLeg {
        val coords = "${from.lon},${from.lat};${to.lon},${to.lat}"
        val url = "$OSRM_BASE/$coords?overview=full&geometries=geojson&steps=true&annotations=false"
        val resp = runCatching { Http.get(url) }.getOrNull()
            ?: throw RouterException("Percorso non disponibile: $fromName → $toName")
        if (resp.status != 200) throw RouterException("Percorso non disponibile: $fromName → $toName")

        val root = runCatching { json.parseToJsonElement(resp.body).jsonObject }.getOrNull()
            ?: throw RouterException("Percorso non disponibile: $fromName → $toName")
        val route = root["routes"]?.jsonArray?.firstOrNull()?.jsonObject
            ?: throw RouterException("Percorso non disponibile: $fromName → $toName")

        val distance = route["distance"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0
        val duration = route["duration"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0

        val geometry = route["geometry"]?.jsonObject?.get("coordinates")?.jsonArray
        val polyline = geometry?.mapNotNull { el ->
            val a = el.jsonArray
            val lon = a.getOrNull(0)?.jsonPrimitive?.content?.toDoubleOrNull()
            val lat = a.getOrNull(1)?.jsonPrimitive?.content?.toDoubleOrNull()
            if (lat != null && lon != null) GeoPoint(lat, lon) else null
        } ?: emptyList()

        val steps = parseSteps(route)

        return RouteLeg.from(
            fromName = fromName,
            toName = toName,
            distanceMeters = distance,
            durationSeconds = duration,
            polyline = polyline,
            steps = steps,
        )
    }

    private fun parseSteps(route: JsonObject): List<RouteStep> {
        val legArray = route["legs"]?.jsonArray ?: return emptyList()
        val out = mutableListOf<RouteStep>()
        for (leg in legArray) {
            val stepArr = leg.jsonObject["steps"]?.jsonArray ?: continue
            for (s in stepArr) {
                val so = s.jsonObject
                val maneuver = so["maneuver"]?.jsonObject ?: continue
                val loc = maneuver["location"]?.jsonArray
                val lon = loc?.getOrNull(0)?.jsonPrimitive?.content?.toDoubleOrNull()
                val lat = loc?.getOrNull(1)?.jsonPrimitive?.content?.toDoubleOrNull()
                if (lat == null || lon == null) continue
                val dist = so["distance"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0
                val name = so["name"]?.jsonPrimitive?.content ?: ""
                val type = maneuver["type"]?.jsonPrimitive?.content ?: ""
                val modifier = maneuver["modifier"]?.jsonPrimitive?.content ?: ""
                val instruction = italianInstruction(type, modifier, name)
                if (instruction.isBlank()) continue
                out.add(RouteStep(instruction = instruction, distanceMeters = dist, latitude = lat, longitude = lon))
            }
        }
        return out
    }

    /** Sintetizza un'istruzione in italiano dal maneuver OSRM (OSRM non dà testo). */
    private fun italianInstruction(type: String, modifier: String, road: String): String {
        val su = if (road.isNotBlank()) " su $road" else ""
        val dir = when (modifier) {
            "left" -> "a sinistra"
            "right" -> "a destra"
            "slight left" -> "leggermente a sinistra"
            "slight right" -> "leggermente a destra"
            "sharp left" -> "secca a sinistra"
            "sharp right" -> "secca a destra"
            "uturn" -> "inversione a U"
            "straight" -> "dritto"
            else -> ""
        }
        return when (type) {
            "depart" -> "Si parte$su"
            "arrive" -> "Arrivo a destinazione"
            "roundabout", "rotary" -> "Alla rotonda prendi l'uscita$su"
            "merge" -> "Immettiti$su"
            "fork" -> if (dir.isNotEmpty()) "Al bivio tieni $dir$su" else "Al bivio prosegui$su"
            "end of road" -> if (dir.isNotEmpty()) "Svolta $dir$su" else "Prosegui$su"
            "continue", "new name" -> if (dir == "inversione a U") "Fai inversione a U" else "Prosegui$su"
            else -> when {
                dir == "inversione a U" -> "Fai inversione a U"
                dir == "dritto" -> "Prosegui dritto$su"
                dir.isNotEmpty() -> "Svolta $dir$su"
                else -> "Prosegui$su"
            }
        }
    }

    // MARK: - Cache percorso navigabile (per routeId)

    private fun cacheFile(context: Context, routeId: String) =
        File(context.filesDir, "nav_$routeId.json")

    fun cacheRoute(context: Context, route: NavigationRoute) {
        runCatching {
            cacheFile(context, route.routeId).writeText(
                AppJson.encodeToString(NavigationRoute.serializer(), route)
            )
        }
    }

    fun cachedRoute(context: Context, routeId: String): NavigationRoute? {
        val f = cacheFile(context, routeId)
        if (!f.exists()) return null
        return runCatching {
            AppJson.decodeFromString(NavigationRoute.serializer(), f.readText())
        }.getOrNull()
    }

    fun deleteCachedRoute(context: Context, routeId: String) {
        runCatching { cacheFile(context, routeId).delete() }
    }

    // MARK: - Cache tratte per coppia di nodi (4 decimali ≈ 11 m)

    private fun legPairFile(context: Context, from: GeocodedWaypoint, to: GeocodedWaypoint): File {
        val key = "legpair_%.4f_%.4f__%.4f_%.4f".format(
            from.latitude, from.longitude, to.latitude, to.longitude
        )
        return File(context.filesDir, "$key.json")
    }

    private fun cachedLeg(context: Context, from: GeocodedWaypoint, to: GeocodedWaypoint): RouteLeg? {
        val f = legPairFile(context, from, to)
        if (!f.exists()) return null
        val leg = runCatching {
            AppJson.decodeFromString(RouteLeg.serializer(), f.readText())
        }.getOrNull() ?: return null
        // Riscrivi i nomi: la cache può venire da un tragitto con etichette diverse
        return leg.copy(fromName = from.name, toName = to.name)
    }

    private fun storeLeg(context: Context, leg: RouteLeg, from: GeocodedWaypoint, to: GeocodedWaypoint) {
        runCatching {
            legPairFile(context, from, to).writeText(
                AppJson.encodeToString(RouteLeg.serializer(), leg)
            )
        }
    }
}
