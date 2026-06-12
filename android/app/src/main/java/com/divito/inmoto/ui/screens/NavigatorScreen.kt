package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.NavigationRoute
import com.divito.inmoto.ui.MapsLauncher
import com.divito.inmoto.ui.components.RouteMap

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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(route?.nome ?: "Navigazione", maxLines = 1, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        when (val s = state) {
            is NavUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Text("Calcolo del percorso…", Modifier.padding(top = 12.dp))
                }
            }

            is NavUiState.Error -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
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

            is NavUiState.Ready -> ReadyContent(s.route, Modifier.padding(padding))
        }
    }
}

@Composable
private fun ReadyContent(route: NavigationRoute, modifier: Modifier) {
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            RouteMap(
                polyline = route.legs.flatMap { it.polylineCoordinates },
                waypoints = route.waypoints.map { it.point },
                modifier = Modifier.fillMaxWidth().height(200.dp),
            )
        }
        item {
            Text(
                "${route.formattedDistance} · ${route.formattedDuration}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        items(route.legs) { leg ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp)) {
                    Text("${leg.fromName} → ${leg.toName}", fontWeight = FontWeight.SemiBold)
                    Text(
                        "%.1f km · %d min".format(leg.distanceMeters / 1000, (leg.durationSeconds / 60).toInt()),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    leg.steps.take(40).forEach { step ->
                        Text("• ${step.instruction}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
        }
    }
}
