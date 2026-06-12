package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.ui.MapsLauncher
import com.divito.inmoto.ui.Routes
import com.divito.inmoto.ui.components.RoutePreviewMap

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RouteDetailScreen(vm: AppViewModel, nav: NavController, routeId: String) {
    val routes by vm.routes.collectAsState()
    val personal by vm.personalRoutes.collectAsState()
    val route = remember(routeId, routes, personal) {
        routes.firstOrNull { it.id == routeId } ?: personal.firstOrNull { it.id == routeId }
    }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(route?.nome ?: "Itinerario", maxLines = 1, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        if (route == null) {
            Box(Modifier.fillMaxSize().padding(padding)) { Text("Itinerario non trovato", Modifier.padding(16.dp)) }
            return@Scaffold
        }
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            RoutePreviewMap(
                waypoints = route.waypointsGmaps.ifEmpty { route.tappe },
                modifier = Modifier.fillMaxWidth().height(200.dp),
            )

            Text("${route.partenza} → ${route.arrivo}", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                if (route.km > 0) StatPill("${route.km} km")
                if (route.durataMin > 0) StatPill(route.durataFormattata)
                if (route.regione.isNotEmpty()) StatPill(route.regione)
            }
            if (route.descrizione.isNotEmpty()) {
                Text(route.descrizione, style = MaterialTheme.typography.bodyMedium)
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { nav.navigate(Routes.navigator(route.id)) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.AutoMirrored.Filled.DirectionsBike, null)
                    Text("  Naviga")
                }
                OutlinedButton(
                    onClick = { MapsLauncher.openRoute(context, route.waypointsGmaps.ifEmpty { route.tappe }) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Filled.Map, null)
                    Text("  Maps")
                }
            }

            if (route.tappe.isNotEmpty()) {
                Text("Punti di passaggio", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                route.tappe.forEachIndexed { i, tappa ->
                    ListItem(
                        headlineContent = { Text(tappa) },
                        leadingContent = { Icon(Icons.Filled.Place, null, tint = MaterialTheme.colorScheme.primary) },
                        overlineContent = { Text("${i + 1}") },
                    )
                }
            }
        }
    }
}

@Composable
private fun StatPill(text: String) {
    AssistChip(onClick = {}, label = { Text(text) }, enabled = false)
}
