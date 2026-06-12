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
fun StageDetailScreen(vm: AppViewModel, nav: NavController, tripId: String, itemId: String) {
    val trips by vm.tripPlans.collectAsState()
    val trip = remember(tripId, trips) { trips.firstOrNull { it.id == tripId } }
    val item = remember(trip, itemId) { trip?.items?.firstOrNull { it.id == itemId } }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(item?.titolo ?: "Tappa", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        if (trip == null || item == null) {
            Box(Modifier.fillMaxSize().padding(padding)) { Text("Tappa non trovata", Modifier.padding(16.dp)) }
            return@Scaffold
        }
        val route = remember(trip, item) { trip.motoRoute(item) }
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            RoutePreviewMap(
                route = route,
                vm = vm,
                modifier = Modifier.fillMaxWidth().height(200.dp),
            )
            Text(item.nome, style = MaterialTheme.typography.titleMedium)
            val meta = buildList {
                if (item.km > 0) add("${item.km} km")
                if (item.durataMin > 0) {
                    val h = item.durataMin / 60; val m = item.durataMin % 60
                    add(if (h > 0) "${h}h ${m}min" else "${m}min")
                }
                if (item.orarioFormattato.isNotEmpty()) add(item.orarioFormattato)
            }.joinToString(" · ")
            if (meta.isNotEmpty()) Text(meta, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (item.nota.isNotEmpty()) Text(item.nota, style = MaterialTheme.typography.bodyMedium)

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { nav.navigate(Routes.navigator(route.id)) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.AutoMirrored.Filled.DirectionsBike, null)
                    Text("  Naviga")
                }
                OutlinedButton(
                    onClick = { MapsLauncher.openRoute(context, item.waypointsGmaps.ifEmpty { item.tappeNomi }) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Filled.Map, null)
                    Text("  Maps")
                }
            }

            if (item.tappeNomi.isNotEmpty()) {
                Text("Punti di passaggio", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                item.tappeNomi.forEachIndexed { i, t ->
                    ListItem(
                        headlineContent = { Text(t) },
                        overlineContent = { Text("${i + 1}") },
                        leadingContent = { Icon(Icons.Filled.Place, null, tint = MaterialTheme.colorScheme.primary) },
                    )
                }
            }
        }
    }
}
