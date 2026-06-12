package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.FavoritePlace
import com.divito.inmoto.ui.MapsLauncher

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritePlacesScreen(vm: AppViewModel, nav: NavController) {
    val places by vm.favoritePlaces.collectAsState()
    var showAdd by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Luoghi preferiti", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showAdd = true }) { Icon(Icons.Filled.Add, "Aggiungi") }
        },
    ) { padding ->
        if (places.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Nessun luogo salvato", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(places, key = { it.id }) { place ->
                    ListItem(
                        headlineContent = { Text(place.tag, fontWeight = FontWeight.SemiBold) },
                        supportingContent = { Text(place.address) },
                        leadingContent = { Icon(Icons.Filled.Place, null, tint = MaterialTheme.colorScheme.primary) },
                        trailingContent = {
                            androidx.compose.foundation.layout.Row {
                                IconButton(onClick = { MapsLauncher.openPlace(context, place.address) }) {
                                    Icon(Icons.Filled.Map, "Apri in Maps")
                                }
                                IconButton(onClick = { vm.deleteFavoritePlace(place) }) {
                                    Icon(Icons.Filled.Delete, "Elimina")
                                }
                            }
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    if (showAdd) {
        AddFavoriteDialog(
            onConfirm = { tag, address ->
                vm.saveFavoritePlace(FavoritePlace(tag = tag, address = address))
                showAdd = false
            },
            onDismiss = { showAdd = false },
        )
    }
}

@Composable
private fun AddFavoriteDialog(onConfirm: (String, String) -> Unit, onDismiss: () -> Unit) {
    var tag by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Nuovo luogo") },
        text = {
            androidx.compose.foundation.layout.Column(
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(value = tag, onValueChange = { tag = it }, label = { Text("Etichetta (es. Casa)") }, singleLine = true)
                OutlinedTextField(value = address, onValueChange = { address = it }, label = { Text("Indirizzo") }, singleLine = true)
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(tag.trim(), address.trim()) }, enabled = tag.isNotBlank() && address.isNotBlank()) {
                Text("Salva")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Annulla") } },
    )
}
