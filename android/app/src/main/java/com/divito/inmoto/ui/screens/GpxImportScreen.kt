package com.divito.inmoto.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.data.GpxImporter
import com.divito.inmoto.data.RouterService
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.TransportMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GpxImportScreen(vm: AppViewModel, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var track by remember { mutableStateOf<GpxImporter.ParsedTrack?>(null) }
    var name by remember { mutableStateOf("") }
    var transport by remember { mutableStateOf(TransportMode.moto) }
    var preview by remember { mutableStateOf<MotoRoute?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    fun rebuildPreview() {
        val t = track ?: return
        preview = GpxImporter.buildRoute(t, name, transport).first
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        error = null
        scope.launch {
            val text = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                }.getOrNull()
            }
            if (text == null) { error = "Impossibile leggere il file."; return@launch }
            val parsed = withContext(Dispatchers.Default) {
                runCatching { GpxImporter.parse(text, "Traccia GPX") }
            }
            parsed.fold(
                onSuccess = {
                    track = it; name = it.name
                    preview = GpxImporter.buildRoute(it, it.name, transport).first
                },
                onFailure = { track = null; preview = null; error = it.message },
            )
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Importa traccia GPX", fontWeight = FontWeight.Bold) },
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
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                "Importa una traccia .gpx (Garmin, Strava, Komoot…). InMoto seguirà esattamente " +
                    "il tracciato registrato, senza ricalcolarlo. I waypoint nominati nel file diventano nodi.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = { picker.launch(arrayOf("*/*")) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.FileOpen, null); Text("  ${if (track == null) "Scegli file GPX…" else "Scegli un altro file"}")
            }

            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

            if (track != null) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Nome del tragitto") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                Text("Tipo di percorso", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = transport == TransportMode.moto,
                        onClick = { transport = TransportMode.moto; rebuildPreview() },
                        label = { Text("In moto") },
                        leadingIcon = { Icon(Icons.Filled.TwoWheeler, null) },
                    )
                    FilterChip(
                        selected = transport == TransportMode.piedi,
                        onClick = { transport = TransportMode.piedi; rebuildPreview() },
                        label = { Text("A piedi") },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null) },
                    )
                }
                Text(
                    "I tempi di percorrenza vengono tarati sul mezzo scelto.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                preview?.let { r ->
                    HorizontalDivider()
                    Text("Anteprima", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        AssistChip(onClick = {}, enabled = false, label = { Text("${r.km} km") })
                        AssistChip(onClick = {}, enabled = false, label = { Text("~${r.durataFormattata}") })
                        AssistChip(onClick = {}, enabled = false, label = { Text("${r.tappe.size} nodi") })
                    }
                    Text("${track!!.points.size} punti · ${r.descrizione}",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                    Button(
                        onClick = {
                            val t = track ?: return@Button
                            val built = GpxImporter.buildRoute(t, name, transport)
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    RouterService.cacheRoute(context, built.second)
                                }
                                vm.savePersonalRoute(built.first)
                                nav.popBackStack()
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Salva tragitto") }
                }
            }
        }
    }
}
