package com.divito.inmoto.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.ui.Routes
import com.divito.inmoto.ui.components.RouteCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeBrowseScreen(vm: AppViewModel, nav: NavController) {
    val routes by vm.routes.collectAsState()
    val regions by vm.regions.collectAsState()
    var query by remember { mutableStateOf("") }
    var selectedRegion by remember { mutableStateOf<String?>(null) }

    val filtered = remember(routes, query, selectedRegion) {
        routes.filter { r ->
            (selectedRegion == null || r.regione.equals(selectedRegion, true)) &&
                (query.isBlank() || listOf(r.nome, r.partenza, r.arrivo, r.regione)
                    .any { it.contains(query, ignoreCase = true) })
        }.sortedByDescending { it.stelle }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Viaggi Personali", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text("Cerca itinerario") },
                    leadingIcon = { Icon(Icons.Filled.Search, null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = selectedRegion == null,
                        onClick = { selectedRegion = null },
                        label = { Text("Tutte") },
                    )
                    regions.forEach { region ->
                        FilterChip(
                            selected = selectedRegion == region,
                            onClick = { selectedRegion = if (selectedRegion == region) null else region },
                            label = { Text(region) },
                        )
                    }
                }
            }
            item {
                Text(
                    "${filtered.size} itinerari",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(filtered, key = { it.id }) { route ->
                RouteCard(route = route, onClick = { nav.navigate(Routes.routeDetail(route.id)) })
            }
        }
    }
}
