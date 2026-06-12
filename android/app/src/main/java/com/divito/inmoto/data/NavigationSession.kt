package com.divito.inmoto.data

import android.content.Context
import android.location.Location
import android.speech.tts.TextToSpeech
import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.GeocodedWaypoint
import com.divito.inmoto.model.NavigationRoute
import com.divito.inmoto.model.RouteLeg
import com.divito.inmoto.model.TurnDirection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Sessione di navigazione attiva. Tutto l'avanzamento (tappe, manovre, arrivo)
 * deriva dal map matching della posizione GPS sul percorso ([RouteGeometry]):
 * tappe raggiunte, tappe saltate e ripresa a metà percorso vengono gestite
 * automaticamente dalla progressione in metri. Port di NavigationSession.swift.
 *
 * Espone lo stato come [StateFlow] osservabile da Compose; gli annunci usano
 * [TextToSpeech] in italiano. Le chiamate ([onLocation], [setMuted]) vanno fatte
 * dal thread principale; il ricalcolo fuori percorso gira su [scope].
 */
class NavigationSession(
    context: Context,
    private val scope: CoroutineScope,
    initial: NavigationRoute,
    muted: Boolean,
) {
    data class UpcomingTurn(
        val key: Int,
        val coordinate: GeoPoint,
        val direction: TurnDirection,
        val instruction: String,
        val isPrimary: Boolean,
    )

    /** Snapshot immutabile per la UI. */
    data class NavState(
        val navRoute: NavigationRoute,
        val routeVersion: Int = 0,
        val currentLegIndex: Int = 0,
        val arrived: Boolean = false,
        val distanceToNextWaypoint: Double = 0.0,
        val distanceToNextStep: Double = 0.0,
        val matched: GeoPoint? = null,
        val course: Double? = null,
        val isOffRoute: Boolean = false,
        val isRerouting: Boolean = false,
        val muted: Boolean = false,
        val currentInstruction: String = "",
        val nextDirection: TurnDirection = TurnDirection.straight,
        val upcomingTurns: List<UpcomingTurn> = emptyList(),
        val nextWaypointName: String = "",
        val progressText: String = "",
        val etaCurrentLeg: String = "",
        val formattedDistance: String = "",
        val remainingFormatted: String = "",
        val progressFraction: Double = 0.0,
    )

    private val appContext = context.applicationContext
    private val _state = MutableStateFlow(NavState(navRoute = initial, muted = muted))
    val state: StateFlow<NavState> = _state.asStateFlow()

    private var navRoute = initial
    private var geometry = RouteGeometry(initial)
    private var routeVersion = 0
    private var currentLegIndex = 0
    private var arrived = false

    private var progressMeters = 0.0
    private var lastMatchPointIndex: Int? = null
    private var lastMatched: GeoPoint? = null
    private var hasInitialFix = false
    private var hasAnnouncedStart = false
    private var offRouteFixCount = 0
    private var lastRerouteAttempt = 0L
    private var announcedRerouteFailure = false
    private var hasAnnouncedArrival = false
    private var isOffRoute = false
    private var isRerouting = false

    private var distanceToNextWaypoint = 0.0
    private var distanceToNextStep = 0.0
    private var upcomingStepIdx: Int? = null

    private val announcedEarly = mutableSetOf<Int>()
    private val announcedNow = mutableSetOf<Int>()

    private val offRouteDistance = 70.0
    private val offRouteFixesNeeded = 3
    private val rerouteCooldownMs = 25_000L

    @Volatile
    var isMuted: Boolean = muted
        private set

    // MARK: - TTS

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val pendingSpeak = ArrayDeque<String>()

    init {
        tts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.ITALIAN
                tts?.setSpeechRate(0.98f)
                ttsReady = true
                while (pendingSpeak.isNotEmpty()) reallySpeak(pendingSpeak.removeFirst())
            }
        }
        publish()
    }

    fun setMuted(value: Boolean) {
        isMuted = value
        if (value) tts?.stop()
        publish()
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    // MARK: - Aggiornamento GPS

    fun onLocation(loc: Location) {
        if (arrived) return
        val coord = GeoPoint(loc.latitude, loc.longitude)
        val m = geometry.match(coord, lastMatchPointIndex, progressMeters - 300) ?: return

        // Fuori percorso: tollera fix imprecisi, poi ricalcola
        val tolerance = max(offRouteDistance, loc.accuracy.toDouble() * 1.5)
        if (m.distanceFromRoute > tolerance) {
            offRouteFixCount += 1
            if (offRouteFixCount >= offRouteFixesNeeded) {
                isOffRoute = true
                requestReroute(loc)
            }
            publish()
            return
        }

        offRouteFixCount = 0
        isOffRoute = false
        announcedRerouteFailure = false
        lastMatchPointIndex = m.pointIndex

        val firstFix = !hasInitialFix
        hasInitialFix = true
        if (firstFix) {
            // Aggancio iniziale: anche a metà percorso, senza riannunciare le tappe superate
            progressMeters = m.progress
            if (!hasAnnouncedStart) {
                hasAnnouncedStart = true
                val dest = shortName(navRoute.waypoints.lastOrNull()?.name ?: "destinazione")
                speak("Navigazione avviata verso $dest.")
            }
        } else if (m.progress > progressMeters || progressMeters - m.progress < 300) {
            // La progressione arretra solo di poco (rumore GPS); i salti avanti sono accettati
            progressMeters = m.progress
        }

        syncLeg(announce = !firstFix)
        updateStep(loc.speed.toDouble())
        updateDistances()
        checkArrival(loc)
        publish(matched = m.coordinate)
    }

    // MARK: - Avanzamento tappe

    private fun syncLeg(announce: Boolean) {
        val newLeg = geometry.legIndex(progressMeters)
        if (newLeg == currentLegIndex) return
        if (newLeg > currentLegIndex && announce) {
            val nextIdx = min(newLeg + 1, navRoute.waypoints.size - 1)
            speak("Tappa raggiunta. Prossima destinazione: ${shortName(navRoute.waypoints[nextIdx].name)}.")
        }
        currentLegIndex = newLeg
    }

    // MARK: - Manovre e annunci

    private fun updateStep(speed: Double) {
        val idx = geometry.upcomingStepIndex(progressMeters)
        if (idx == null) {
            upcomingStepIdx = null
            distanceToNextStep = 0.0
            return
        }
        upcomingStepIdx = idx
        val step = geometry.steps[idx]
        distanceToNextStep = step.progress - progressMeters

        // Annunci basati sul tempo alla manovra, non su soglie fisse
        val v = if (speed > 1) speed else 13.0          // fermo/sconosciuto: ~47 km/h
        val nowDist = min(280.0, max(60.0, v * 7))      // ~7 secondi prima
        val earlyDist = min(1300.0, max(320.0, v * 25)) // ~25 secondi prima

        if (distanceToNextStep < nowDist) {
            if (idx !in announcedNow) {
                announcedNow.add(idx)
                announcedEarly.add(idx)
                speak(step.instruction)
            }
        } else if (distanceToNextStep < earlyDist && idx !in announcedEarly) {
            announcedEarly.add(idx)
            speak("Tra ${voiceDistance(distanceToNextStep)}, ${step.instruction}")
        }
    }

    private fun updateDistances() {
        val nextWp = min(currentLegIndex + 1, geometry.waypointProgress.size - 1)
        distanceToNextWaypoint = max(0.0, geometry.waypointProgress[nextWp] - progressMeters)
    }

    private fun checkArrival(loc: Location) {
        if (hasAnnouncedArrival) return
        val remaining = geometry.totalMeters - progressMeters
        val last = navRoute.waypoints.lastOrNull()
        val direct = if (last != null) {
            val r = FloatArray(1)
            Location.distanceBetween(loc.latitude, loc.longitude, last.latitude, last.longitude, r)
            r[0].toDouble()
        } else {
            Double.POSITIVE_INFINITY
        }
        if (remaining < 40 || (direct < 60 && currentLegIndex == navRoute.legs.size - 1)) {
            hasAnnouncedArrival = true
            arrived = true
            speak("Sei arrivato a destinazione. Buona moto!")
        }
    }

    // MARK: - Ricalcolo fuori percorso

    private fun requestReroute(loc: Location) {
        if (isRerouting) return
        val now = System.currentTimeMillis()
        if (now - lastRerouteAttempt < rerouteCooldownMs) return
        lastRerouteAttempt = now
        isRerouting = true
        publish()

        val notStarted = !hasInitialFix || progressMeters < 250
        val targetIdx = if (notStarted) 0 else min(currentLegIndex + 1, navRoute.waypoints.size - 1)
        val target = navRoute.waypoints[targetIdx]
        val here = GeoPoint(loc.latitude, loc.longitude)

        scope.launch {
            val connector = try {
                withContext(Dispatchers.IO) { RouterService.connectorLeg(here, target) }
            } catch (e: Exception) {
                isRerouting = false
                if (!announcedRerouteFailure) {
                    announcedRerouteFailure = true
                    speak("Sei fuori percorso e non riesco a ricalcolare. Rientra sul tracciato.")
                }
                publish()
                return@launch
            }
            applyReroute(connector, targetIdx, loc)
        }
    }

    private fun applyReroute(connector: RouteLeg, targetWaypointIndex: Int, loc: Location) {
        val waypoints = navRoute.waypoints.toMutableList()
        val legs = navRoute.legs.toMutableList()
        val here = GeocodedWaypoint(
            name = "Posizione attuale",
            latitude = loc.latitude,
            longitude = loc.longitude,
        )

        if (targetWaypointIndex == 0) {
            // Non ancora partiti: tratta di avvicinamento prima della partenza
            waypoints.add(0, here)
            legs.add(0, connector)
        } else {
            // Sostituisci la tratta corrente: posizione attuale → prossima tappa
            waypoints[targetWaypointIndex - 1] = here
            legs[targetWaypointIndex - 1] = connector
        }

        navRoute = NavigationRoute(navRoute.routeId, navRoute.routeName, waypoints, legs)
        geometry = RouteGeometry(navRoute)

        lastMatchPointIndex = null
        hasInitialFix = false
        progressMeters = 0.0
        currentLegIndex = max(0, targetWaypointIndex - 1)
        announcedEarly.clear()
        announcedNow.clear()
        offRouteFixCount = 0
        isOffRoute = false
        isRerouting = false
        routeVersion += 1
        speak("Percorso ricalcolato.")
        publish()
    }

    // MARK: - Pubblicazione stato

    private fun publish(matched: GeoPoint? = lastMatched) {
        lastMatched = matched
        val turns = upcomingTurns()
        _state.value = NavState(
            navRoute = navRoute,
            routeVersion = routeVersion,
            currentLegIndex = currentLegIndex,
            arrived = arrived,
            distanceToNextWaypoint = distanceToNextWaypoint,
            distanceToNextStep = distanceToNextStep,
            matched = matched,
            course = if (matched != null) geometry.bearingAtProgress(progressMeters) else null,
            isOffRoute = isOffRoute,
            isRerouting = isRerouting,
            muted = isMuted,
            currentInstruction = currentInstruction(),
            nextDirection = turns.firstOrNull()?.direction ?: TurnDirection.straight,
            upcomingTurns = turns,
            nextWaypointName = nextWaypointName(),
            progressText = progressText(),
            etaCurrentLeg = etaCurrentLeg(),
            formattedDistance = formatMeters(distanceToNextWaypoint),
            remainingFormatted = formatMeters(max(0.0, geometry.totalMeters - progressMeters)),
            progressFraction = if (geometry.totalMeters > 0) min(1.0, progressMeters / geometry.totalMeters) else 0.0,
        )
    }

    // MARK: - Valori derivati per la UI

    private fun currentInstruction(): String {
        if (arrived) return "Destinazione raggiunta"
        val idx = upcomingStepIdx
        if (idx != null && idx < geometry.steps.size) return geometry.steps[idx].instruction
        if (currentLegIndex >= navRoute.legs.size) return "Destinazione raggiunta"
        return "Prosegui verso ${shortName(navRoute.legs[currentLegIndex].toName)}"
    }

    private fun upcomingTurns(): List<UpcomingTurn> {
        val start = upcomingStepIdx ?: return emptyList()
        val out = ArrayList<UpcomingTurn>()
        var i = start
        while (i < geometry.steps.size && out.size < 2) {
            val s = geometry.steps[i]
            val dir = TurnDirection.parse(s.instruction)
            if (dir != TurnDirection.straight || i == start) {
                out.add(
                    UpcomingTurn(
                        key = routeVersion * 100_000 + i,
                        coordinate = s.coordinate,
                        direction = dir,
                        instruction = s.instruction,
                        isPrimary = out.isEmpty(),
                    ),
                )
            }
            i += 1
        }
        return out
    }

    private fun nextWaypointName(): String {
        val idx = min(currentLegIndex + 1, navRoute.waypoints.size - 1)
        return shortName(navRoute.waypoints[idx].name)
    }

    private fun progressText(): String = "Tappa ${currentLegIndex + 1} / ${navRoute.legs.size + 1}"

    private fun etaCurrentLeg(): String {
        if (currentLegIndex >= navRoute.legs.size) return ""
        val legStart = geometry.waypointProgress[currentLegIndex]
        val legEnd = geometry.waypointProgress[currentLegIndex + 1]
        val legLen = max(1.0, legEnd - legStart)
        val fraction = min(1.0, max(0.0, (legEnd - progressMeters) / legLen))
        val mins = max(0, (navRoute.legs[currentLegIndex].durationSeconds * fraction).toInt() / 60)
        return if (mins < 60) "$mins min" else "${mins / 60}h ${mins % 60}min"
    }

    // MARK: - Helper

    private fun formatMeters(m: Double): String =
        if (m < 1000) "${m.roundToInt()} m" else "%.1f km".format(m / 1000)

    private fun voiceDistance(meters: Double): String {
        if (meters < 950) {
            val rounded = max(100, (meters / 100).roundToInt() * 100)
            return "$rounded metri"
        }
        val km = meters / 1000
        if (km < 1.5) return "un chilometro"
        return "${km.roundToInt()} chilometri"
    }

    private fun speak(text: String) {
        if (isMuted) return
        if (ttsReady) reallySpeak(text) else pendingSpeak.add(text)
    }

    private fun reallySpeak(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_ADD, null, text.hashCode().toString())
    }

    private fun shortName(full: String): String = full.substringBefore(",").ifEmpty { full }
}
