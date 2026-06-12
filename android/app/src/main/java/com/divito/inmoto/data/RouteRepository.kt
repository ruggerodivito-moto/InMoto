package com.divito.inmoto.data

import android.content.Context
import com.divito.inmoto.model.FavoritePlace
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.RoutesResponse
import com.divito.inmoto.model.TripPlan
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.util.UUID

/**
 * Persistenza offline + sync, port del RouteStore di iOS.
 * Espone StateFlow consumati dalla UI Compose.
 */
class RouteRepository(private val context: Context) {

    private val _routes = MutableStateFlow<List<MotoRoute>>(emptyList())
    val routes: StateFlow<List<MotoRoute>> = _routes.asStateFlow()

    private val _regions = MutableStateFlow<List<String>>(emptyList())
    val regions: StateFlow<List<String>> = _regions.asStateFlow()

    private val _personalRoutes = MutableStateFlow<List<MotoRoute>>(emptyList())
    val personalRoutes: StateFlow<List<MotoRoute>> = _personalRoutes.asStateFlow()

    private val _favoritePlaces = MutableStateFlow<List<FavoritePlace>>(emptyList())
    val favoritePlaces: StateFlow<List<FavoritePlace>> = _favoritePlaces.asStateFlow()

    private val _tripPlans = MutableStateFlow<List<TripPlan>>(emptyList())
    val tripPlans: StateFlow<List<TripPlan>> = _tripPlans.asStateFlow()

    private val settings = AppSettings(context)

    private val cacheFile get() = File(context.cacheDir, "routes_cache.json")
    private val personalFile get() = File(context.filesDir, "personal_routes.json")
    private val favoritesFile get() = File(context.filesDir, "favorite_places.json")
    private val tripPlansFile get() = File(context.filesDir, "trip_plans.json")

    // ── Caricamento iniziale ────────────────────────────────────────────────
    fun loadInitial() {
        if (!loadFromCache()) {
            loadFromAssets()
        }
        loadPersonalRoutes()
        loadFavoritePlaces()
        loadTripPlans()
    }

    private fun loadFromAssets() {
        runCatching {
            val text = context.assets.open("routes.json").bufferedReader().use { it.readText() }
            val loaded = AppJson.decodeFromString(ListSerializer(MotoRoute.serializer()), text)
            _routes.value = loaded
            updateRegions()
        }.onFailure { it.printStackTrace() }
    }

    private fun loadFromCache(): Boolean {
        if (!cacheFile.exists()) return false
        return runCatching {
            val loaded = AppJson.decodeFromString(
                ListSerializer(MotoRoute.serializer()), cacheFile.readText()
            )
            _routes.value = loaded
            updateRegions()
            true
        }.getOrDefault(false)
    }

    private fun saveToCache(newRoutes: List<MotoRoute>) {
        runCatching {
            cacheFile.writeText(AppJson.encodeToString(ListSerializer(MotoRoute.serializer()), newRoutes))
        }
    }

    private fun updateRegions() {
        _regions.value = _routes.value.map { it.regione }
            .filter { it.isNotEmpty() }
            .distinct()
            .sorted()
    }

    // ── Tragitti personali ──────────────────────────────────────────────────
    private fun loadPersonalRoutes() {
        if (!personalFile.exists()) return
        runCatching {
            _personalRoutes.value = AppJson.decodeFromString(
                ListSerializer(MotoRoute.serializer()), personalFile.readText()
            )
        }
    }

    fun savePersonalRoute(route: MotoRoute) {
        _personalRoutes.value = _personalRoutes.value + route
        persistPersonal()
    }

    fun deletePersonalRoute(route: MotoRoute) {
        _personalRoutes.value = _personalRoutes.value.filterNot { it.id == route.id }
        persistPersonal()
    }

    private fun persistPersonal() {
        runCatching {
            personalFile.writeText(
                AppJson.encodeToString(ListSerializer(MotoRoute.serializer()), _personalRoutes.value)
            )
        }
    }

    // ── Luoghi preferiti ────────────────────────────────────────────────────
    private fun loadFavoritePlaces() {
        if (!favoritesFile.exists()) return
        runCatching {
            _favoritePlaces.value = AppJson.decodeFromString(
                ListSerializer(FavoritePlace.serializer()), favoritesFile.readText()
            )
        }
    }

    fun saveFavoritePlace(place: FavoritePlace) {
        _favoritePlaces.value = _favoritePlaces.value + place
        persistFavorites()
    }

    fun updateFavoritePlace(place: FavoritePlace) {
        _favoritePlaces.value = _favoritePlaces.value.map { if (it.id == place.id) place else it }
        persistFavorites()
    }

    fun deleteFavoritePlace(place: FavoritePlace) {
        _favoritePlaces.value = _favoritePlaces.value.filterNot { it.id == place.id }
        persistFavorites()
    }

    private fun persistFavorites() {
        runCatching {
            favoritesFile.writeText(
                AppJson.encodeToString(ListSerializer(FavoritePlace.serializer()), _favoritePlaces.value)
            )
        }
    }

    // ── Viaggi (roadbook) ───────────────────────────────────────────────────
    private fun loadTripPlans() {
        if (!tripPlansFile.exists()) return
        runCatching {
            _tripPlans.value = AppJson.decodeFromString(
                ListSerializer(TripPlan.serializer()), tripPlansFile.readText()
            )
        }
    }

    fun saveTripPlan(plan: TripPlan) {
        _tripPlans.value = _tripPlans.value + plan
        persistTripPlans()
    }

    fun renameTripPlan(plan: TripPlan, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        _tripPlans.value = _tripPlans.value.map {
            if (it.id == plan.id) it.copy(nome = trimmed) else it
        }
        persistTripPlans()
    }

    fun deleteTripPlan(plan: TripPlan) {
        _tripPlans.value = _tripPlans.value.filterNot { it.id == plan.id }
        // ripulisci i percorsi di navigazione cacheati delle tappe
        for (item in plan.tappe) {
            RouterService.deleteCachedRoute(context, "${plan.id}_${item.id}")
        }
        persistTripPlans()
    }

    private fun persistTripPlans() {
        runCatching {
            tripPlansFile.writeText(
                AppJson.encodeToString(ListSerializer(TripPlan.serializer()), _tripPlans.value)
            )
        }
    }

    // ── Sync dal server ─────────────────────────────────────────────────────
    sealed interface SyncResult {
        data class Success(val count: Int) : SyncResult
        data class Failure(val message: String) : SyncResult
    }

    suspend fun syncFromServer(): SyncResult {
        if (!settings.isConfigured) {
            return SyncResult.Failure("Configura l'URL del server nelle Impostazioni")
        }
        return runCatching {
            val resp = Http.get(
                settings.apiURL("/api/mobile/moto/routes"),
                headers = mapOf("X-Moto-Key" to settings.apiKey),
            )
            if (resp.status != 200) return SyncResult.Failure("Errore server (HTTP ${resp.status})")
            val result = AppJson.decodeFromString(RoutesResponse.serializer(), resp.body)
            if (result.ok) {
                _routes.value = result.routes
                updateRegions()
                saveToCache(result.routes)
                SyncResult.Success(result.routes.size)
            } else {
                SyncResult.Failure(result.error ?: "Errore sconosciuto")
            }
        }.getOrElse { SyncResult.Failure("Errore: ${it.message}") }
    }

    // ── Luoghi unici (per autocomplete) ─────────────────────────────────────
    val allLocations: List<String>
        get() = buildSet {
            for (r in _routes.value) {
                r.partenza.trim().takeIf { it.isNotEmpty() }?.let { add(it) }
                r.arrivo.trim().takeIf { it.isNotEmpty() }?.let { add(it) }
            }
        }.sorted()

    // ── Filtro locale ───────────────────────────────────────────────────────
    fun filtered(
        regione: String?, partenza: String?, arrivo: String?,
        kmMax: Int?, durataMax: Int?,
    ): List<MotoRoute> = _routes.value.filter { r ->
        if (!regione.isNullOrEmpty() && !r.regione.equals(regione, ignoreCase = true)) return@filter false
        if (!partenza.isNullOrEmpty() && !r.partenza.contains(partenza, ignoreCase = true)) return@filter false
        if (!arrivo.isNullOrEmpty() && !r.arrivo.contains(arrivo, ignoreCase = true)) return@filter false
        if (kmMax != null && r.km > kmMax) return@filter false
        if (durataMax != null && r.durataMin > durataMax) return@filter false
        true
    }.sortedByDescending { it.stelle }

    // ── Composizione tragitto locale ────────────────────────────────────────
    private val scenicRoutes: List<MotoRoute>
        get() {
            val blocked = listOf("autostrada", "pedaggio", "casello", "tangenziale", "raccordo")
            return _routes.value.filter { r ->
                val text = listOf(r.nome, r.descrizione, r.partenza, r.arrivo)
                    .joinToString(" ").lowercase()
                blocked.none { text.contains(it) }
            }
        }

    fun composeLocalRoute(startText: String, endText: String): MotoRoute {
        fun fuzzy(a: String, b: String): Boolean {
            val x = a.lowercase(); val y = b.lowercase()
            return x.contains(y) || y.contains(x)
        }

        val pool = scenicRoutes
        val startCandidates = pool.filter { fuzzy(it.partenza, startText) }.sortedByDescending { it.stelle }
        val endCandidates = pool.filter { fuzzy(it.arrivo, endText) }.sortedByDescending { it.stelle }

        // Fase 1 — unico route che copre entrambi
        pool.firstOrNull { fuzzy(it.partenza, startText) && fuzzy(it.arrivo, endText) }?.let { return it }

        // Fase 2 — catena diretta
        for (s in startCandidates.take(8)) for (e in endCandidates.take(8)) {
            if (s.id != e.id && fuzzy(s.arrivo, e.partenza)) {
                return buildComposed(listOf(s, e), startText, endText)
            }
        }

        // Fase 3 — catena con bridge
        for (s in startCandidates.take(5)) for (e in endCandidates.take(5)) {
            if (s.id == e.id) continue
            for (bridge in pool) {
                if (bridge.id == s.id || bridge.id == e.id) continue
                if (fuzzy(bridge.partenza, s.arrivo) && fuzzy(bridge.arrivo, e.partenza)) {
                    return buildComposed(listOf(s, bridge, e), startText, endText)
                }
            }
        }

        // Fase 4 — fallback
        val legs = mutableListOf<MotoRoute>()
        startCandidates.firstOrNull()?.let { legs.add(it) }
        endCandidates.firstOrNull()?.let { if (it.id != legs.firstOrNull()?.id) legs.add(it) }

        // Fase 5 — top scenic per stelle
        if (legs.isEmpty()) {
            legs.addAll(pool.sortedByDescending { it.stelle }.take(2))
        }
        return buildComposed(legs, startText, endText)
    }

    private fun buildComposed(legs: List<MotoRoute>, start: String, end: String): MotoRoute {
        val totalKm = legs.sumOf { it.km }
        val totalMin = legs.sumOf { it.durataMin }
        val avgStelle = if (legs.isEmpty()) 4.0 else legs.sumOf { it.stelle } / legs.size
        val legNames = legs.joinToString(" → ") { it.nome }
        val regioni = legs.map { it.regione }.toSortedSet().joinToString(", ")
        val n = legs.size
        return MotoRoute(
            id = UUID.randomUUID().toString(),
            nome = "Da $start a $end",
            partenza = start,
            arrivo = end,
            regione = regioni,
            km = totalKm,
            durataMin = totalMin,
            difficolta = "Media",
            stelle = avgStelle,
            descrizione = "Tragitto in $n tapp${if (n == 1) "a" else "e"}: $legNames",
            tappe = legs.flatMap { it.tappe },
            waypointsGmaps = legs.flatMap { it.waypointsGmaps },
            tags = legs.flatMap { it.tags }.toSortedSet().toList(),
            fonte = "Composto InMoto",
            stagione = legs.firstOrNull()?.stagione ?: "Tutto l'anno",
            isCustom = true,
            legKm = legs.map { it.km },
            legMin = legs.map { it.durataMin },
        )
    }
}
