package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.TripPlan
import com.divito.inmoto.model.TripPlanItem
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoadbookImportScreen(vm: AppViewModel, nav: NavController) {
    var text by remember { mutableStateOf("") }
    var parsing by remember { mutableStateOf(false) }
    var parsed by remember { mutableStateOf<TripPlan?>(null) }
    var nome by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Importa roadbook", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Incolla il testo del roadbook (sezioni TAPPA / PAUSA / ARRIVO, orari, " +
                    "km/durata, link Google Maps). Poi premi Analizza.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = text,
                onValueChange = { text = it; parsed = null; error = null },
                label = { Text("Testo del roadbook") },
                modifier = Modifier.fillMaxWidth().height(220.dp),
            )
            Button(
                onClick = {
                    scope.launch {
                        parsing = true; error = null
                        val result = vm.parseRoadbook(text)
                        parsing = false
                        if (result == null) {
                            error = "Nessuna tappa riconosciuta. Controlla il formato (serve almeno una TAPPA)."
                        } else {
                            parsed = result
                            nome = result.nome
                        }
                    }
                },
                enabled = text.isNotBlank() && !parsing,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (parsing) {
                    CircularProgressIndicator(Modifier.height(20.dp), strokeWidth = 2.dp)
                    Text("  Analisi in corso…")
                } else {
                    Text("Analizza")
                }
            }

            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }

            parsed?.let { plan ->
                HorizontalDivider()
                Text("Anteprima", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = nome,
                    onValueChange = { nome = it },
                    label = { Text("Nome del viaggio") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (plan.sottotitolo.isNotEmpty()) Text(plan.sottotitolo)
                plan.items.forEach { item ->
                    PreviewItem(item)
                }
                Button(
                    onClick = {
                        vm.saveTripPlan(plan.copy(nome = nome.ifBlank { plan.nome }))
                        nav.popBackStack()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Salva viaggio") }
            }
        }
    }
}

@Composable
private fun PreviewItem(item: TripPlanItem) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            val o = buildList {
                add(item.titolo)
                if (item.orarioFormattato.isNotEmpty()) add(item.orarioFormattato)
            }.joinToString(" · ")
            Text(o, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            Text(item.nome, fontWeight = FontWeight.SemiBold)
            if (item.kind == TripPlanItem.Kind.tappa) {
                val s = buildList {
                    if (item.km > 0) add("${item.km} km")
                    add("${item.tappeNomi.size} punti")
                }.joinToString(" · ")
                Text(s, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
