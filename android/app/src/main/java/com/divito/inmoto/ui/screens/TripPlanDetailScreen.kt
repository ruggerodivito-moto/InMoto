package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Flag
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
import com.divito.inmoto.model.TripPlanItem
import com.divito.inmoto.ui.MapsLauncher
import com.divito.inmoto.ui.Routes

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TripPlanDetailScreen(vm: AppViewModel, nav: NavController, tripId: String) {
    val trips by vm.tripPlans.collectAsState()
    val trip = remember(tripId, trips) { trips.firstOrNull { it.id == tripId } }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(trip?.nome ?: "Viaggio", maxLines = 1, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        if (trip == null) {
            Box(Modifier.fillMaxSize().padding(padding)) { Text("Viaggio non trovato", Modifier.padding(16.dp)) }
            return@Scaffold
        }
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Column {
                    if (trip.sottotitolo.isNotEmpty()) {
                        Text(trip.sottotitolo, style = MaterialTheme.typography.titleMedium)
                    }
                    val meta = buildList {
                        add("${trip.tappe.size} tappe")
                        if (trip.totaleKm > 0) add("${trip.totaleKm} km")
                        if (trip.durataFormattata.isNotEmpty()) add(trip.durataFormattata)
                    }.joinToString(" · ")
                    Text(meta, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(trip.items, key = { it.id }) { item ->
                TimelineRow(item) {
                    when (item.kind) {
                        TripPlanItem.Kind.tappa -> nav.navigate(Routes.stageDetail(trip.id, item.id))
                        else -> {
                            val q = item.waypointsGmaps.firstOrNull() ?: item.nome
                            MapsLauncher.openPlace(context, q)
                        }
                    }
                }
            }
            if (trip.notaFinale.isNotEmpty()) {
                item {
                    Card(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                        Column(Modifier.padding(14.dp)) {
                            Text("Per tornare", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                            Text(trip.notaFinale, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TimelineRow(item: TripPlanItem, onClick: () -> Unit) {
    val icon = when (item.kind) {
        TripPlanItem.Kind.tappa -> Icons.Filled.Place
        TripPlanItem.Kind.pausa -> Icons.Filled.Coffee
        TripPlanItem.Kind.arrivo -> Icons.Filled.Flag
    }
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        ListItem(
            overlineContent = {
                val o = buildList {
                    add(item.titolo)
                    if (item.orarioFormattato.isNotEmpty()) add(item.orarioFormattato)
                }.joinToString(" · ")
                Text(o)
            },
            headlineContent = { Text(item.nome, fontWeight = FontWeight.SemiBold) },
            supportingContent = {
                val s = buildList {
                    if (item.km > 0) add("${item.km} km")
                    if (item.durataMin > 0) {
                        val h = item.durataMin / 60; val m = item.durataMin % 60
                        add(if (h > 0) "${h}h ${m}min" else "${m}min")
                    }
                    if (item.nota.isNotEmpty()) add(item.nota)
                }.joinToString(" · ")
                if (s.isNotEmpty()) Text(s)
            },
            leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        )
    }
}
