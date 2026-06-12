package com.divito.inmoto

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.divito.inmoto.data.AppSettings
import com.divito.inmoto.data.RoadbookParser
import com.divito.inmoto.data.RouteRepository
import com.divito.inmoto.model.FavoritePlace
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.TripPlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** ViewModel app: possiede il repository ed espone gli StateFlow alla UI. */
class AppViewModel(app: Application) : AndroidViewModel(app) {

    val repo = RouteRepository(app)
    val settings = AppSettings(app)

    val routes: StateFlow<List<MotoRoute>> get() = repo.routes
    val regions: StateFlow<List<String>> get() = repo.regions
    val personalRoutes: StateFlow<List<MotoRoute>> get() = repo.personalRoutes
    val favoritePlaces: StateFlow<List<FavoritePlace>> get() = repo.favoritePlaces
    val tripPlans: StateFlow<List<TripPlan>> get() = repo.tripPlans

    private val _syncMessage = MutableStateFlow<String?>(null)
    val syncMessage: StateFlow<String?> = _syncMessage.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    init {
        viewModelScope.launch(Dispatchers.IO) { repo.loadInitial() }
    }

    // ── Viaggi ──────────────────────────────────────────────────────────────
    fun saveTripPlan(plan: TripPlan) = repo.saveTripPlan(plan)
    fun renameTripPlan(plan: TripPlan, newName: String) = repo.renameTripPlan(plan, newName)
    fun deleteTripPlan(plan: TripPlan) = viewModelScope.launch(Dispatchers.IO) { repo.deleteTripPlan(plan) }

    /** Analizza un roadbook testuale (risolve i link in rete). */
    suspend fun parseRoadbook(text: String): TripPlan? =
        withContext(Dispatchers.IO) { RoadbookParser.parse(text) }

    // ── Tragitti personali ──────────────────────────────────────────────────
    fun savePersonalRoute(route: MotoRoute) = repo.savePersonalRoute(route)
    fun deletePersonalRoute(route: MotoRoute) = repo.deletePersonalRoute(route)
    fun composeLocalRoute(start: String, end: String): MotoRoute =
        repo.composeLocalRoute(start, end)

    // ── Preferiti ───────────────────────────────────────────────────────────
    fun saveFavoritePlace(place: FavoritePlace) = repo.saveFavoritePlace(place)
    fun updateFavoritePlace(place: FavoritePlace) = repo.updateFavoritePlace(place)
    fun deleteFavoritePlace(place: FavoritePlace) = repo.deleteFavoritePlace(place)

    // ── Sync server ─────────────────────────────────────────────────────────
    fun syncFromServer() {
        viewModelScope.launch {
            _isSyncing.value = true
            _syncMessage.value = "Sincronizzazione in corso…"
            when (val r = repo.syncFromServer()) {
                is RouteRepository.SyncResult.Success ->
                    _syncMessage.value = "${r.count} itinerari aggiornati"
                is RouteRepository.SyncResult.Failure ->
                    _syncMessage.value = r.message
            }
            _isSyncing.value = false
        }
    }

    fun routeById(id: String): MotoRoute? =
        routes.value.firstOrNull { it.id == id }
            ?: personalRoutes.value.firstOrNull { it.id == id }

    fun tripById(id: String): TripPlan? = tripPlans.value.firstOrNull { it.id == id }

    /**
     * Risolve una MotoRoute navigabile dall'id. Gestisce sia gli id semplici
     * (itinerari/tragitti) sia gli id-tappa "<tripId>_<itemId>" generati da
     * TripPlan.motoRoute().
     */
    fun navigableRoute(routeId: String): MotoRoute? {
        routeById(routeId)?.let { return it }
        // id-tappa: <tripId>_<itemId>
        for (trip in tripPlans.value) {
            for (item in trip.tappe) {
                if ("${trip.id}_${item.id}" == routeId) return trip.motoRoute(item)
            }
        }
        return null
    }

    /**
     * Costruisce (o recupera dalla cache) il NavigationRoute per una MotoRoute:
     * geocoding dei waypoint + calcolo tratte OSRM. I/O su Dispatchers.IO.
     */
    suspend fun buildNavigationRoute(route: MotoRoute): com.divito.inmoto.model.NavigationRoute =
        withContext(Dispatchers.IO) {
            com.divito.inmoto.data.RouterService.cachedRoute(getApplication(), route.id)?.let { return@withContext it }
            val inputs = route.waypointsGmaps.ifEmpty { route.tappe }
                .ifEmpty { listOf(route.partenza, route.arrivo).filter { it.isNotEmpty() } }
            val waypoints = com.divito.inmoto.data.RouterService.geocodeWaypointsMixed(inputs)
            val legs = com.divito.inmoto.data.RouterService.computeLegs(getApplication(), waypoints)
            val nav = com.divito.inmoto.model.NavigationRoute(
                routeId = route.id,
                routeName = route.nome,
                waypoints = waypoints,
                legs = legs,
            )
            com.divito.inmoto.data.RouterService.cacheRoute(getApplication(), nav)
            nav
        }
}
