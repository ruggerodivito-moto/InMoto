package com.divito.inmoto.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.RoundaboutRight
import androidx.compose.material.icons.filled.Straight
import androidx.compose.material.icons.filled.TurnLeft
import androidx.compose.material.icons.filled.TurnRight
import androidx.compose.material.icons.filled.TurnSharpLeft
import androidx.compose.material.icons.filled.TurnSharpRight
import androidx.compose.material.icons.filled.TurnSlightLeft
import androidx.compose.material.icons.filled.TurnSlightRight
import androidx.compose.material.icons.filled.UTurnLeft
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.data.LocationProvider
import com.divito.inmoto.data.NavigationSession
import com.divito.inmoto.data.RouteGeometry
import com.divito.inmoto.data.RouterService
import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.GeocodedWaypoint
import com.divito.inmoto.model.NavigationRoute
import com.divito.inmoto.model.TurnDirection
import com.divito.inmoto.ui.MapsLauncher
import com.divito.inmoto.ui.components.NavigationMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

private sealed interface NavUiState {
    data object Loading : NavUiState
    data class Ready(val route: NavigationRoute) : NavUiState
    data class Error(val message: String) : NavUiState
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NavigatorScreen(vm: AppViewModel, nav: NavController, routeId: String) {
    val context = LocalContext.current
    val route = remember(routeId) { vm.navigableRoute(routeId) }
    var state by remember { mutableStateOf<NavUiState>(NavUiState.Loading) }

    LaunchedEffect(routeId) {
        val r = route
        if (r == null) {
            state = NavUiState.Error("Percorso non trovato")
            return@LaunchedEffect
        }
        state = NavUiState.Loading
        state = runCatching { vm.buildNavigationRoute(r) }
            .fold({ NavUiState.Ready(it) }, { NavUiState.Error(it.message ?: "Errore nel calcolo del percorso") })
    }

    when (val s = state) {
        is NavUiState.Loading -> LoadingOrError(route?.nome ?: "Navigazione", onBack = { nav.popBackStack() }) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Text("Calcolo del percorso…", Modifier.padding(top = 12.dp))
            }
        }

        is NavUiState.Error -> LoadingOrError(route?.nome ?: "Navigazione", onBack = { nav.popBackStack() }) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
                Text(s.message, color = MaterialTheme.colorScheme.error)
                route?.let {
                    Button(
                        onClick = { MapsLauncher.openRoute(context, it.waypointsGmaps.ifEmpty { it.tappe }) },
                        modifier = Modifier.padding(top = 16.dp),
                    ) { Icon(Icons.Filled.Map, null); Text("  Apri in Google Maps") }
                }
            }
        }

        is NavUiState.Ready -> NavigationGate(
            route = s.route,
            onBack = { nav.popBackStack() },
            onOpenMaps = { route?.let { MapsLauncher.openRoute(context, it.waypointsGmaps.ifEmpty { it.tappe }) } },
        )
    }
}

/**
 * Prima della navigazione: se la posizione attuale è nota ed è lontana (>300 m)
 * dal primo nodo, chiede se anteporre la posizione come partenza oppure seguire
 * solo il percorso originale. Equivalente del prompt iOS.
 */
@Composable
private fun NavigationGate(route: NavigationRoute, onBack: () -> Unit, onOpenMaps: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val provider = remember { LocationProvider(context) }

    var finalRoute by remember(route.routeId) { mutableStateOf<NavigationRoute?>(null) }
    var promptDistance by remember(route.routeId) { mutableStateOf<Double?>(null) }
    var here by remember(route.routeId) { mutableStateOf<GeoPoint?>(null) }
    var preparing by remember(route.routeId) { mutableStateOf(false) }

    LaunchedEffect(route.routeId) {
        val first = route.waypoints.firstOrNull()
        if (hasLocationPermission(context) && first != null) {
            val loc = provider.oneShot()
            if (loc != null) {
                val d = RouteGeometry.distance(GeoPoint(loc.latitude, loc.longitude), first.point)
                if (d > 300) {
                    here = GeoPoint(loc.latitude, loc.longitude)
                    promptDistance = d
                    return@LaunchedEffect
                }
            }
        }
        finalRoute = route
    }

    val fr = finalRoute
    if (fr != null) {
        LiveNavigation(route = fr, onBack = onBack, onOpenMaps = onOpenMaps)
        return
    }

    // Schermo d'attesa mentre si decide / prepara il collegamento
    LoadingOrError(route.routeName, onBack = onBack) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Text(if (preparing) "Calcolo collegamento…" else "Preparazione…", Modifier.padding(top = 12.dp))
        }
    }

    val dist = promptDistance
    if (dist != null && !preparing) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text("Non sei al punto di partenza") },
            text = {
                Text(
                    "Sei a circa ${fmtKm(dist)} dall'inizio del percorso. Vuoi aggiungere la tua " +
                        "posizione attuale come partenza, oppure vedere solo il percorso originale?",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val h = here; val first = route.waypoints.firstOrNull()
                    if (h == null || first == null) { finalRoute = route; return@TextButton }
                    preparing = true
                    scope.launch {
                        val merged = runCatching {
                            val connector = withContext(Dispatchers.IO) {
                                RouterService.connectorLeg(h, first, route.transport)
                            }
                            val hereWp = GeocodedWaypoint("Posizione attuale", h.lat, h.lon)
                            route.copy(
                                waypoints = listOf(hereWp) + route.waypoints,
                                legs = listOf(connector) + route.legs,
                            )
                        }.getOrDefault(route)
                        finalRoute = merged
                    }
                }) { Text("Aggiungi la mia posizione") }
            },
            dismissButton = {
                TextButton(onClick = { finalRoute = route }) { Text("Solo il percorso originale") }
            },
        )
    }
}

private fun fmtKm(meters: Double): String =
    if (meters < 1000) "${meters.roundToInt()} m" else "%.1f km".format(meters / 1000)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LoadingOrError(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { content() }
    }
}

@Composable
private fun LiveNavigation(route: NavigationRoute, onBack: () -> Unit, onOpenMaps: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val session = remember(route.routeId) { NavigationSession(context, scope, route, false) }
    val provider = remember { LocationProvider(context) }
    val navState by session.state.collectAsState()
    var follow by remember { mutableStateOf(true) }
    var hasPermission by remember { mutableStateOf(hasLocationPermission(context)) }

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        hasPermission = it
    }
    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    LaunchedEffect(Unit) {
        if (!hasPermission) launcher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        // Permesso notifiche (Android 13+): le notifiche di navigazione si
        // rispecchiano anche sull'orologio Wear OS abbinato.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    // Colleziona la posizione solo a permesso concesso; il flow si chiude all'uscita.
    LaunchedEffect(hasPermission) {
        if (hasPermission) provider.locationUpdates().collect { session.onLocation(it) }
    }
    DisposableEffect(Unit) { onDispose { session.shutdown() } }

    Box(Modifier.fillMaxSize()) {
        NavigationMap(
            polyline = navState.navRoute.legs.flatMap { it.polylineCoordinates },
            matched = navState.matched,
            course = navState.course,
            follow = follow,
            routeVersion = navState.routeVersion,
            onUserPan = { follow = false },
            modifier = Modifier.fillMaxSize(),
        )

        ManeuverCard(
            navState = navState,
            onBack = onBack,
            modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(12.dp),
        )

        // Comandi: muta voce + ricentra.
        Column(
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!follow) {
                SmallFloatingActionButton(onClick = { follow = true }) {
                    Icon(Icons.Filled.MyLocation, "Ricentra")
                }
            }
            SmallFloatingActionButton(onClick = { session.setMuted(!navState.muted) }) {
                Icon(
                    if (navState.muted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
                    if (navState.muted) "Riattiva voce" else "Muta voce",
                )
            }
        }

        // Stato GPS / permesso / arrivo, in basso a sinistra.
        BottomStatus(
            navState = navState,
            hasPermission = hasPermission,
            onOpenMaps = onOpenMaps,
            modifier = Modifier.align(Alignment.BottomStart).padding(16.dp),
        )
    }
}

@Composable
private fun ManeuverCard(navState: NavigationSession.NavState, onBack: () -> Unit, modifier: Modifier) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f))) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") }
                Icon(
                    navState.nextDirection.maneuverIcon(),
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    navState.currentInstruction.ifEmpty { "Avvio navigazione…" },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
                if (navState.distanceToNextStep > 0) {
                    Text(
                        fmtMeters(navState.distanceToNextStep),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                SummaryItem(navState.progressText)
                SummaryItem(navState.etaCurrentLeg.ifEmpty { "—" })
                SummaryItem("↑ ${navState.remainingFormatted}")
                SummaryItem("→ ${navState.nextWaypointName}")
            }
            if (navState.isRerouting || navState.isOffRoute) {
                Text(
                    if (navState.isRerouting) "Ricalcolo del percorso…" else "Fuori percorso",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun SummaryItem(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 1,
    )
}

@Composable
private fun BottomStatus(
    navState: NavigationSession.NavState,
    hasPermission: Boolean,
    onOpenMaps: () -> Unit,
    modifier: Modifier,
) {
    when {
        navState.arrived -> StatusChip("✅ Arrivato a destinazione", modifier)
        !hasPermission -> AssistChip(
            onClick = onOpenMaps,
            label = { Text("Permesso GPS negato — Apri in Maps") },
            leadingIcon = { Icon(Icons.Filled.Map, null) },
            modifier = modifier,
        )
        navState.matched == null -> StatusChip("In attesa del GPS…", modifier)
    }
}

@Composable
private fun StatusChip(text: String, modifier: Modifier) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 2.dp,
    ) {
        Text(text, Modifier.padding(horizontal = 12.dp, vertical = 8.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

private fun hasLocationPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

private fun fmtMeters(m: Double): String =
    if (m < 1000) "${m.roundToInt()} m" else "%.1f km".format(m / 1000)

private fun TurnDirection.maneuverIcon(): ImageVector = when (this) {
    TurnDirection.straight -> Icons.Filled.Straight
    TurnDirection.depart -> Icons.Filled.Navigation
    TurnDirection.slightLeft -> Icons.Filled.TurnSlightLeft
    TurnDirection.left -> Icons.Filled.TurnLeft
    TurnDirection.sharpLeft -> Icons.Filled.TurnSharpLeft
    TurnDirection.slightRight -> Icons.Filled.TurnSlightRight
    TurnDirection.right -> Icons.Filled.TurnRight
    TurnDirection.sharpRight -> Icons.Filled.TurnSharpRight
    TurnDirection.uTurn -> Icons.Filled.UTurnLeft
    TurnDirection.roundabout -> Icons.Filled.RoundaboutRight
    TurnDirection.arrive -> Icons.Filled.Flag
}
