package com.divito.inmoto.data

import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.NavigationRoute
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Geometria "appiattita" di una [NavigationRoute]: tutte le tratte in un unico
 * polyline con distanze progressive. È la base del map matching: la posizione GPS
 * viene proiettata sulla linea e l'avanzamento (tappe, step, annunci) deriva dalla
 * progressione in metri lungo il percorso, mai da soglie puntuali che in moto si
 * saltano facilmente. Port 1:1 di RouteGeometry.swift.
 */
class RouteGeometry(route: NavigationRoute) {

    data class FlatStep(
        val legIndex: Int,
        val progress: Double,          // metri dall'inizio del percorso
        val instruction: String,
        val coordinate: GeoPoint,
    )

    data class Match(
        val pointIndex: Int,           // primo punto del segmento agganciato
        val coordinate: GeoPoint,      // proiezione sulla linea
        val progress: Double,          // metri dall'inizio
        val distanceFromRoute: Double, // distanza perpendicolare dalla linea
    )

    val points: List<GeoPoint>
    val cumulative: List<Double>       // metri dall'inizio, per ogni punto
    val waypointProgress: List<Double> // metri dall'inizio, per ogni waypoint
    val steps: List<FlatStep>          // ordinati per progress

    val totalMeters: Double get() = cumulative.lastOrNull() ?: 0.0

    init {
        val pts = ArrayList<GeoPoint>()
        val cum = ArrayList<Double>()
        val wpProg = ArrayList<Double>().apply { add(0.0) }
        val legRanges = ArrayList<IntRange>() // primo..ultimo indice punto (inclusivi)

        for (leg in route.legs) {
            val firstIdx = max(0, pts.size - 1)
            for (c in leg.polylineCoordinates) {
                // Le tratte consecutive condividono il punto di giunzione: salta i duplicati
                val last = pts.lastOrNull()
                if (last != null && abs(last.lat - c.lat) < 1e-7 && abs(last.lon - c.lon) < 1e-7) continue
                if (last != null) cum.add(cum[cum.size - 1] + distance(last, c)) else cum.add(0.0)
                pts.add(c)
            }
            legRanges.add(firstIdx..max(firstIdx, pts.size - 1))
            wpProg.add(cum.lastOrNull() ?: 0.0)
        }

        val flat = ArrayList<FlatStep>()
        route.legs.forEachIndexed { li, leg ->
            val range = legRanges[li]
            for (step in leg.steps) {
                val prog = if (range.first < range.last) {
                    bestMatch(step.point, pts, cum, range.first until range.last)?.progress ?: wpProg[li]
                } else {
                    wpProg[li]
                }
                flat.add(FlatStep(li, prog, step.instruction, step.point))
            }
        }
        flat.sortBy { it.progress }

        points = pts
        cumulative = cum
        waypointProgress = wpProg
        steps = flat
    }

    /**
     * Proietta una coordinata sul percorso. Cerca prima in una finestra attorno
     * all'ultimo aggancio; se fallisce estende la ricerca in avanti e poi a tutto
     * il percorso. Port di RouteGeometry.match.
     */
    fun match(coordinate: GeoPoint, nearPointIndex: Int?, minProgress: Double): Match? {
        if (points.size < 2) return null
        val lastPoint = points.size - 1

        if (nearPointIndex != null) {
            val lo = max(0, nearPointIndex - 40)
            val hi = min(lastPoint, nearPointIndex + 400)
            if (lo < hi) {
                val m = bestMatch(coordinate, points, cumulative, lo until hi)
                if (m != null && m.distanceFromRoute < 70) return m
            }
        }

        // Ricerca "in avanti": solo sui tratti non ancora superati
        if (minProgress > 0) {
            val startIdx = cumulative.indexOfFirst { it >= minProgress }.let { if (it < 0) 0 else it }
            if (startIdx < lastPoint) {
                val m = bestMatch(coordinate, points, cumulative, startIdx until lastPoint)
                if (m != null && m.distanceFromRoute < 70) return m
            }
        }

        return bestMatch(coordinate, points, cumulative, 0 until lastPoint)
    }

    /** Indice della tratta corrente data la progressione (nodo "raggiunto" già
     * `reachThreshold` metri prima, per annunciare in tempo). */
    fun legIndex(progress: Double, reachThreshold: Double = 30.0): Int {
        if (waypointProgress.size <= 2) return 0
        var idx = 0
        for (j in 1 until waypointProgress.size - 1) {
            if (progress + reachThreshold >= waypointProgress[j]) idx = j
        }
        return idx
    }

    /** Prossima manovra non ancora superata. */
    fun upcomingStepIndex(afterProgress: Double): Int? {
        val i = steps.indexOfFirst { it.progress > afterProgress + 8 }
        return if (i < 0) null else i
    }

    /** Direzione di marcia (gradi, 0=N) lungo il percorso alla progressione data,
     * per la camera course-up. Guarda un po' avanti per essere stabile. */
    fun bearingAtProgress(progress: Double, lookahead: Double = 35.0): Double? {
        if (points.size < 2) return null
        val iA = cumulative.indexOfFirst { it >= progress }.let { if (it < 0) points.size - 1 else it }
        val iB = cumulative.indexOfFirst { it >= progress + lookahead }.let { if (it < 0) points.size - 1 else it }
        val a = points[min(iA, points.size - 1)]
        val b = points[min(max(iB, iA + 1), points.size - 1)]
        if (abs(a.lat - b.lat) < 1e-9 && abs(a.lon - b.lon) < 1e-9) return null
        return bearing(a, b)
    }

    companion object {
        /** Distanza in metri (Haversine). */
        fun distance(a: GeoPoint, b: GeoPoint): Double {
            val r = 6_371_000.0
            val dLat = Math.toRadians(b.lat - a.lat)
            val dLon = Math.toRadians(b.lon - a.lon)
            val la1 = Math.toRadians(a.lat)
            val la2 = Math.toRadians(b.lat)
            val h = sin(dLat / 2).pow(2) + cos(la1) * cos(la2) * sin(dLon / 2).pow(2)
            return 2 * r * asin(min(1.0, sqrt(h)))
        }

        /** Rotta iniziale in gradi (0=N) da a verso b. */
        fun bearing(a: GeoPoint, b: GeoPoint): Double {
            val la1 = Math.toRadians(a.lat)
            val la2 = Math.toRadians(b.lat)
            val dLon = Math.toRadians(b.lon - a.lon)
            val y = sin(dLon) * cos(la2)
            val x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
            return (Math.toDegrees(atan2(y, x)) + 360) % 360
        }

        private fun bestMatch(
            c: GeoPoint,
            points: List<GeoPoint>,
            cumulative: List<Double>,
            segments: IntRange,
        ): Match? {
            if (segments.isEmpty()) return null
            // Proiezione planare locale: sufficiente per distanze di pochi km
            val kLat = 111_132.0
            val kLon = 111_320.0 * cos(c.lat * PI / 180)

            var best: Match? = null
            for (i in segments) {
                val a = points[i]
                val b = points[i + 1]
                val ax = (a.lon - c.lon) * kLon
                val ay = (a.lat - c.lat) * kLat
                val bx = (b.lon - c.lon) * kLon
                val by = (b.lat - c.lat) * kLat
                val dx = bx - ax
                val dy = by - ay
                val lenSq = dx * dx + dy * dy
                val t = if (lenSq > 0) min(1.0, max(0.0, -(ax * dx + ay * dy) / lenSq)) else 0.0
                val px = ax + dx * t
                val py = ay + dy * t
                val dist = sqrt(px * px + py * py)
                val cur = best
                if (cur == null || dist < cur.distanceFromRoute) {
                    best = Match(
                        pointIndex = i,
                        coordinate = GeoPoint(
                            lat = a.lat + (b.lat - a.lat) * t,
                            lon = a.lon + (b.lon - a.lon) * t,
                        ),
                        progress = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t,
                        distanceFromRoute = dist,
                    )
                }
            }
            return best
        }
    }
}
