package com.divito.inmoto.model

import kotlinx.serialization.Serializable
import java.util.UUID

/** Coordinata geografica semplice (lat/lon). Convertita in LatLng MapLibre al bordo UI. */
@Serializable
data class GeoPoint(val lat: Double, val lon: Double)

// MARK: - TurnDirection

/** Tipo di manovra. L'icona concreta è scelta nel layer UI (Material icons). */
enum class TurnDirection {
    straight, slightLeft, left, sharpLeft,
    slightRight, right, sharpRight,
    uTurn, roundabout, arrive, depart;

    companion object {
        /** Parsa istruzioni in italiano o inglese (MKDirections / OSRM). */
        fun parse(instruction: String): TurnDirection {
            val t = instruction.lowercase()
            if (t.contains("arriv") || t.contains("destinazione") || t.contains("destination")) return arrive
            if (t.contains("torna indietro") || t.contains("inversione") || t.contains("u-turn")) return uTurn
            if (t.contains("rotonda") || t.contains("roundabout")) return roundabout
            if ((t.contains("legger") || t.contains("slight")) && (t.contains("sinistra") || t.contains("left"))) return slightLeft
            if ((t.contains("legger") || t.contains("slight")) && (t.contains("destra") || t.contains("right"))) return slightRight
            if (t.contains("sinistra") || t.contains("left")) return left
            if (t.contains("destra") || t.contains("right")) return right
            if (t.contains("parte") || t.contains("depart")) return depart
            return straight
        }
    }
}

@Serializable
data class GeocodedWaypoint(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val note: String? = null,   // nota/descrizione del nodo (es. dai waypoint GPX)
) {
    val point: GeoPoint get() = GeoPoint(latitude, longitude)
}

@Serializable
data class RouteStep(
    val id: String = UUID.randomUUID().toString(),
    val instruction: String,
    val distanceMeters: Double,
    val latitude: Double,
    val longitude: Double,
) {
    val point: GeoPoint get() = GeoPoint(latitude, longitude)
}

@Serializable
data class RouteLeg(
    val id: String = UUID.randomUUID().toString(),
    val fromName: String,
    val toName: String,
    val distanceMeters: Double,
    val durationSeconds: Double,
    val polylinePoints: List<List<Double>>,   // [[lat, lon], …]
    val steps: List<RouteStep>,
) {
    val polylineCoordinates: List<GeoPoint>
        get() = polylinePoints.mapNotNull { p ->
            if (p.size == 2) GeoPoint(p[0], p[1]) else null
        }

    companion object {
        fun from(
            fromName: String,
            toName: String,
            distanceMeters: Double,
            durationSeconds: Double,
            polyline: List<GeoPoint>,
            steps: List<RouteStep>,
        ) = RouteLeg(
            fromName = fromName,
            toName = toName,
            distanceMeters = distanceMeters,
            durationSeconds = durationSeconds,
            polylinePoints = polyline.map { listOf(it.lat, it.lon) },
            steps = steps,
        )
    }
}

@Serializable
data class NavigationRoute(
    val routeId: String,
    val routeName: String,
    val waypoints: List<GeocodedWaypoint>,
    val legs: List<RouteLeg>,
    val transport: String? = null,   // "moto" | "piedi" (null = moto)
) {
    /** Mezzo del percorso (default moto se non specificato). */
    val transportMode: TransportMode get() = TransportMode.from(transport)

    val totalDistanceMeters: Double get() = legs.sumOf { it.distanceMeters }
    val totalDurationSeconds: Double get() = legs.sumOf { it.durationSeconds }

    val formattedDistance: String get() = "%.0f km".format(totalDistanceMeters / 1000)

    val formattedDuration: String
        get() {
            val total = totalDurationSeconds.toInt()
            val h = total / 3600
            val m = (total % 3600) / 60
            return when {
                h == 0 -> "$m min"
                m == 0 -> "${h}h"
                else -> "${h}h ${m}min"
            }
        }
}

// MARK: - FavoritePlace

@Serializable
data class FavoritePlace(
    val id: String = UUID.randomUUID().toString(),
    var tag: String,       // etichetta (es. "Casa", "Lavoro")
    var address: String,   // indirizzo testuale
)
