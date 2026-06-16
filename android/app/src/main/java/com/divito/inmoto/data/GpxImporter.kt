package com.divito.inmoto.data

import android.util.Xml
import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.GeocodedWaypoint
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.NavigationRoute
import com.divito.inmoto.model.RouteLeg
import com.divito.inmoto.model.RouteStep
import com.divito.inmoto.model.TransportMode
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.util.UUID
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Importa una traccia GPX (Garmin, Strava, Komoot…) seguendo esattamente il
 * tracciato registrato: i punti diventano la polyline di navigazione, senza
 * ricalcolo stradale. Se il file contiene waypoint nominati (`<wpt>` con
 * nome/descrizione) questi diventano i nodi del percorso; altrimenti nodi
 * sintetici per ETA/avanzamento. Port di GPXImporter.swift.
 */
object GpxImporter {

    data class NamedPoint(val name: String, val note: String?, val coordinate: GeoPoint)
    data class ParsedTrack(val name: String, val points: List<GeoPoint>, val waypoints: List<NamedPoint>)

    class GpxException(message: String) : Exception(message)

    private data class Boundary(val idx: Int, val name: String, val note: String?)

    // MARK: - Parsing

    fun parse(text: String, fallbackName: String): ParsedTrack {
        val trkpts = ArrayList<GeoPoint>()
        val rtepts = ArrayList<GeoPoint>()
        val wpts = ArrayList<GeoPoint>()
        val named = ArrayList<NamedPoint>()
        var trackName: String? = null

        var inWpt = false
        var wptCoord: GeoPoint? = null
        var wptName = ""
        var wptDesc = ""

        try {
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(StringReader(text))
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> when (parser.name) {
                        "trkpt" -> coord(parser)?.let { trkpts.add(it) }
                        "rtept" -> coord(parser)?.let { rtepts.add(it) }
                        "wpt" -> { inWpt = true; wptCoord = coord(parser); wptName = ""; wptDesc = "" }
                        "name" ->
                            if (inWpt) wptName = parser.nextText()
                            else if (trackName == null) trackName = parser.nextText()
                        "desc" -> if (inWpt) wptDesc = parser.nextText()
                        "cmt" -> if (inWpt && wptDesc.isBlank()) wptDesc = parser.nextText()
                    }
                    XmlPullParser.END_TAG -> if (parser.name == "wpt") {
                        wptCoord?.let { c ->
                            named.add(
                                NamedPoint(
                                    name = wptName.trim().ifBlank { "Nodo ${named.size + 1}" },
                                    note = wptDesc.trim().ifBlank { null },
                                    coordinate = c,
                                ),
                            )
                        }
                        inWpt = false
                        wptCoord = null
                    }
                }
                event = parser.next()
            }
        } catch (e: Exception) {
            throw GpxException("File GPX non valido o illeggibile.")
        }

        val pts = when {
            trkpts.size >= 2 -> trkpts
            rtepts.size >= 2 -> rtepts
            else -> wpts
        }
        if (pts.size < 2) throw GpxException("Il file GPX non contiene una traccia con punti sufficienti.")
        val name = (trackName?.trim()).let { if (it.isNullOrBlank()) fallbackName else it }
        return ParsedTrack(name, pts, named)
    }

    private fun coord(p: XmlPullParser): GeoPoint? {
        val lat = p.getAttributeValue(null, "lat")?.toDoubleOrNull()
        val lon = p.getAttributeValue(null, "lon")?.toDoubleOrNull()
        return if (lat != null && lon != null && abs(lat) <= 90 && abs(lon) <= 180) GeoPoint(lat, lon) else null
    }

    // MARK: - Costruzione percorso

    fun buildRoute(track: ParsedTrack, displayName: String, transport: TransportMode): Pair<MotoRoute, NavigationRoute> {
        val pts = track.points
        val name = displayName.trim().ifBlank { track.name }

        val cum = DoubleArray(pts.size)
        for (i in 1 until pts.size) cum[i] = cum[i - 1] + RouteGeometry.distance(pts[i - 1], pts[i])
        val total = cum.last()
        val totalKm = total / 1000

        val boundaries = ArrayList(
            if (track.waypoints.isEmpty()) syntheticBoundaries(pts, cum, total, totalKm, name)
            else namedBoundaries(pts, track.waypoints, name),
        )

        // Salvaguardia anelli: con soli 2 nodi e partenza ≈ arrivo, una singola
        // tratta farebbe scattare il falso "arrivo". Inserisci un nodo a metà.
        if (boundaries.size == 2 &&
            RouteGeometry.distance(pts[boundaries[0].idx], pts[boundaries[1].idx]) < 100
        ) {
            val midIdx = cum.indexOfFirst { it >= total / 2 }.let { if (it < 0) pts.size / 2 else it }
            if (midIdx in 2 until pts.size - 1) {
                boundaries.add(1, Boundary(midIdx, "Metà percorso", null))
            }
        }

        val waypoints = boundaries.map {
            GeocodedWaypoint(name = it.name, latitude = pts[it.idx].lat, longitude = pts[it.idx].lon, note = it.note)
        }

        val avgSpeed = transport.avgSpeedKmh
        val legs = ArrayList<RouteLeg>()
        for (i in 0 until boundaries.size - 1) {
            val a = boundaries[i].idx; val b = boundaries[i + 1].idx
            val slice = pts.subList(a, b + 1)
            val legMeters = cum[b] - cum[a]
            val legSeconds = legMeters / 1000 / avgSpeed * 3600
            legs.add(
                RouteLeg.from(
                    fromName = boundaries[i].name,
                    toName = boundaries[i + 1].name,
                    distanceMeters = legMeters,
                    durationSeconds = legSeconds,
                    polyline = slice,
                    steps = synthesizeSteps(slice),
                ),
            )
        }

        val routeId = UUID.randomUUID().toString()
        val navRoute = NavigationRoute(
            routeId = routeId,
            routeName = name,
            waypoints = waypoints,
            legs = legs,
            transport = transport.id,
        )

        val nNodi = track.waypoints.size
        val descrizione = if (nNodi > 0)
            "Traccia GPX (${transport.label.lowercase()}) · ${pts.size} punti · $nNodi nod${if (nNodi == 1) "o" else "i"} dal file · segue esattamente il tracciato."
        else
            "Traccia GPX (${transport.label.lowercase()}) · ${pts.size} punti · segue esattamente il tracciato registrato."

        val route = MotoRoute(
            id = routeId,
            nome = name,
            partenza = waypoints.firstOrNull()?.name ?: "Partenza",
            arrivo = waypoints.lastOrNull()?.name ?: name,
            regione = "",
            km = maxOf(1, totalKm.roundToInt()),
            durataMin = maxOf(1, (total / 1000 / avgSpeed * 60).toInt()),
            difficolta = "Media",
            stelle = 0.0,
            descrizione = descrizione,
            tappe = waypoints.map { it.name },
            waypointsGmaps = waypoints.map { "${it.latitude},${it.longitude}" },
            tags = listOf("gpx", "personale"),
            fonte = "GPX importato",
            stagione = "Tutto l'anno",
            isCustom = true,
            legKm = legs.map { maxOf(1, (it.distanceMeters / 1000).toInt()) },
            legMin = legs.map { maxOf(1, (it.durationSeconds / 60).toInt()) },
            mezzo = transport.id,
        )
        return route to navRoute
    }

    // MARK: - Nodi

    private fun namedBoundaries(pts: List<GeoPoint>, named: List<NamedPoint>, endName: String): List<Boundary> {
        val n = pts.size
        val snap = maxOf(2, n / 50)
        var startName = "Partenza"; var startNote: String? = null
        var finalName = endName; var finalNote: String? = null
        val interior = ArrayList<Boundary>()

        for (wp in named) {
            val idx = nearestIndex(wp.coordinate, pts)
            when {
                idx <= snap -> { startName = wp.name; startNote = wp.note }
                idx >= n - 1 - snap -> { finalName = wp.name; finalNote = wp.note }
                else -> interior.add(Boundary(idx, wp.name, wp.note))
            }
        }
        interior.sortBy { it.idx }

        val result = ArrayList<Boundary>()
        result.add(Boundary(0, startName, startNote))
        for (b in interior) if (b.idx - result.last().idx >= 2) result.add(b)
        val last = result.last()
        if (n - 1 - last.idx < 2) {
            result[result.size - 1] = Boundary(n - 1, last.name, last.note)
        } else {
            result.add(Boundary(n - 1, finalName, finalNote))
        }
        return result
    }

    private fun syntheticBoundaries(
        pts: List<GeoPoint>, cum: DoubleArray, total: Double, totalKm: Double, endName: String,
    ): List<Boundary> {
        val segCount = maxOf(2, minOf(8, (totalKm / 4).roundToInt()))
        val idxs = ArrayList<Int>().apply { add(0) }
        for (s in 1 until segCount) {
            val target = total * s / segCount
            val idx = cum.indexOfFirst { it >= target }.let { if (it < 0) pts.size - 1 else it }
            if (idx > idxs.last()) idxs.add(idx)
        }
        if (idxs.last() != pts.size - 1) idxs.add(pts.size - 1)

        return idxs.mapIndexed { k, idx ->
            when (k) {
                0 -> Boundary(idx, "Partenza", null)
                idxs.size - 1 -> Boundary(idx, endName, null)
                else -> Boundary(idx, "km ${(cum[idx] / 1000).roundToInt()}", null)
            }
        }
    }

    private fun nearestIndex(c: GeoPoint, pts: List<GeoPoint>): Int {
        var best = 0
        var bestD = Double.MAX_VALUE
        for (i in pts.indices) {
            val d = RouteGeometry.distance(c, pts[i])
            if (d < bestD) { bestD = d; best = i }
        }
        return best
    }

    // MARK: - Manovre sintetizzate

    private fun synthesizeSteps(points: List<GeoPoint>): List<RouteStep> {
        if (points.size < 3) return emptyList()
        val simplified = douglasPeucker(points, 18.0)
        if (simplified.size < 3) return emptyList()
        val steps = ArrayList<RouteStep>()
        for (i in 1 until simplified.size - 1) {
            val inB = bearing(simplified[i - 1], simplified[i])
            val outB = bearing(simplified[i], simplified[i + 1])
            var delta = outB - inB
            while (delta > 180) delta -= 360
            while (delta < -180) delta += 360
            val mag = abs(delta)
            if (mag < 30) continue
            val right = delta > 0
            val instruction = when {
                mag < 50 -> if (right) "Leggermente a destra" else "Leggermente a sinistra"
                mag < 115 -> if (right) "Gira a destra" else "Gira a sinistra"
                mag < 165 -> if (right) "Svolta secca a destra" else "Svolta secca a sinistra"
                else -> "Fai inversione di marcia"
            }
            steps.add(RouteStep(instruction = instruction, distanceMeters = 0.0,
                latitude = simplified[i].lat, longitude = simplified[i].lon))
        }
        return steps
    }

    private fun bearing(a: GeoPoint, b: GeoPoint): Double {
        val lat1 = Math.toRadians(a.lat); val lat2 = Math.toRadians(b.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return Math.toDegrees(atan2(y, x))
    }

    private fun douglasPeucker(pts: List<GeoPoint>, epsilon: Double): List<GeoPoint> {
        if (pts.size <= 2) return pts
        val keep = BooleanArray(pts.size)
        keep[0] = true; keep[pts.size - 1] = true
        val stack = ArrayDeque<Pair<Int, Int>>()
        stack.addLast(0 to pts.size - 1)
        while (stack.isNotEmpty()) {
            val (s, e) = stack.removeLast()
            if (e <= s + 1) continue
            var maxD = 0.0; var idx = -1
            for (i in s + 1 until e) {
                val d = perpDistance(pts[i], pts[s], pts[e])
                if (d > maxD) { maxD = d; idx = i }
            }
            if (maxD > epsilon && idx != -1) {
                keep[idx] = true
                stack.addLast(s to idx)
                stack.addLast(idx to e)
            }
        }
        return pts.filterIndexed { i, _ -> keep[i] }
    }

    private fun perpDistance(p: GeoPoint, a: GeoPoint, b: GeoPoint): Double {
        val kLat = 111_132.0
        val kLon = 111_320.0 * cos(p.lat * Math.PI / 180)
        val ax = (a.lon - p.lon) * kLon; val ay = (a.lat - p.lat) * kLat
        val bx = (b.lon - p.lon) * kLon; val by = (b.lat - p.lat) * kLat
        val dx = bx - ax; val dy = by - ay
        val len = sqrt(dx * dx + dy * dy)
        if (len < 1e-6) return sqrt(ax * ax + ay * ay)
        return abs(dx * ay - dy * ax) / len
    }
}
