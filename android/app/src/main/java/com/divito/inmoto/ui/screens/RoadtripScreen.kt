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
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.TripPlan
import com.divito.inmoto.ui.Routes

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoadtripScreen(vm: AppViewModel, nav: NavController) {
    val trips by vm.tripPlans.collectAsState()
    val personal by vm.personalRoutes.collectAsState()
    var showAddMenu by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<TripPlan?>(null) }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Bikers Liguria Roadtrip", fontWeight = FontWeight.Bold) }) },
        floatingActionButton = {
            Box {
                FloatingActionButton(onClick = { showAddMenu = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "Aggiungi")
                }
                DropdownMenu(expanded = showAddMenu, onDismissRequest = { showAddMenu = false }) {
                    DropdownMenuItem(
                        text = { Text("Importa roadbook (viaggio)") },
                        leadingIcon = { Icon(Icons.Filled.Route, null) },
                        onClick = { showAddMenu = false; nav.navigate(Routes.ROADBOOK_IMPORT) },
                    )
                    DropdownMenuItem(
                        text = { Text("Componi viaggio dai tragitti") },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsBike, null) },
                        onClick = { showAddMenu = false; nav.navigate(Routes.COMPOSE_TRIP) },
                    )
                }
            }
        },
    ) { padding ->
        if (trips.isEmpty() && personal.isEmpty()) {
            EmptyState(Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (trips.isNotEmpty()) {
                item { SectionHeader("Viaggi") }
                items(trips, key = { it.id }) { trip ->
                    TripRow(
                        trip = trip,
                        onClick = { nav.navigate(Routes.tripDetail(trip.id)) },
                        onRename = { renameTarget = trip },
                        onDelete = { vm.deleteTripPlan(trip) },
                    )
                }
            }
            if (personal.isNotEmpty()) {
                item { SectionHeader("Tragitti personali") }
                items(personal, key = { it.id }) { route ->
                    PersonalRouteRow(
                        route = route,
                        onClick = { nav.navigate(Routes.routeDetail(route.id)) },
                        onDelete = { vm.deletePersonalRoute(route) },
                    )
                }
            }
        }
    }

    renameTarget?.let { trip ->
        RenameDialog(
            current = trip.nome,
            onConfirm = { vm.renameTripPlan(trip, it); renameTarget = null },
            onDismiss = { renameTarget = null },
        )
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
    )
}

@Composable
private fun TripRow(trip: TripPlan, onClick: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        ListItem(
            headlineContent = { Text(trip.nome, fontWeight = FontWeight.SemiBold) },
            supportingContent = {
                val parts = buildList {
                    if (trip.sottotitolo.isNotEmpty()) add(trip.sottotitolo)
                    add("${trip.tappe.size} tappe")
                    if (trip.totaleKm > 0) add("${trip.totaleKm} km")
                    if (trip.durataFormattata.isNotEmpty()) add(trip.durataFormattata)
                }
                Text(parts.joinToString(" · "))
            },
            leadingContent = { Icon(Icons.Filled.Route, null, tint = MaterialTheme.colorScheme.primary) },
            trailingContent = {
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Edit, "Opzioni") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Rinomina") }, onClick = { menu = false; onRename() })
                        DropdownMenuItem(text = { Text("Elimina") }, onClick = { menu = false; onDelete() })
                    }
                }
            },
        )
    }
}

@Composable
private fun PersonalRouteRow(route: MotoRoute, onClick: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        ListItem(
            headlineContent = { Text(route.nome, fontWeight = FontWeight.SemiBold) },
            supportingContent = { Text("${route.partenza} → ${route.arrivo} · ${route.km} km") },
            leadingContent = { Icon(Icons.Filled.Map, null, tint = MaterialTheme.colorScheme.secondary) },
            trailingContent = {
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Delete, "Opzioni") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Elimina") }, onClick = { menu = false; onDelete() })
                    }
                }
            },
        )
    }
}

@Composable
private fun EmptyState(modifier: Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Filled.Route, null, modifier = Modifier.padding(bottom = 12.dp), tint = MaterialTheme.colorScheme.primary)
        Text("Nessun viaggio o tragitto", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(
            "Usa il + per importare un roadbook o comporre un viaggio dai tragitti.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
fun RenameDialog(current: String, onConfirm: (String) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rinomina viaggio") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("Nome del viaggio") },
                singleLine = true,
            )
        },
        confirmButton = { TextButton(onClick = { onConfirm(text) }) { Text("Salva") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Annulla") } },
    )
}
