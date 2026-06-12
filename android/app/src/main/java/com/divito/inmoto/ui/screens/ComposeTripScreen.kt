package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.MotoRoute

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComposeTripScreen(vm: AppViewModel, nav: NavController) {
    var start by remember { mutableStateOf("") }
    var end by remember { mutableStateOf("") }
    var composed by remember { mutableStateOf<MotoRoute?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Componi viaggio", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Compone un tragitto panoramico concatenando gli itinerari dal database (evita autostrade e pedaggi).",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = start, onValueChange = { start = it; composed = null },
                label = { Text("Partenza") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = end, onValueChange = { end = it; composed = null },
                label = { Text("Arrivo") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { composed = vm.composeLocalRoute(start.trim(), end.trim()) },
                enabled = start.isNotBlank() && end.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Componi") }

            composed?.let { route ->
                HorizontalDivider()
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp)) {
                        Text(route.nome, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text("${route.km} km · ${route.durataFormattata}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(route.descrizione, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                    }
                }
                Button(
                    onClick = { vm.savePersonalRoute(route); nav.popBackStack() },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Salva tra i tragitti personali") }
            }
        }
    }
}
