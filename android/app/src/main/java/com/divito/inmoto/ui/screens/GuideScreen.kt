package com.divito.inmoto.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GuideScreen(nav: NavController) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Come aggiungere un viaggio", fontWeight = FontWeight.Bold) },
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
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Section("Formato roadbook", body)
            Section("Esempio", example)
        }
    }
}

@Composable
private fun Section(title: String, text: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Text(text, style = MaterialTheme.typography.bodyMedium)
}

private const val body = """Un viaggio è una sequenza di tappe navigabili e pause con orari.
Usa le sezioni in maiuscolo:

• TAPPA n — un tratto da guidare. Riga col nome (es. "Carcare - Colle della Maddalena"), poi opzionalmente: un link Google Maps del percorso, le metriche "2h 15' 148Km", l'orario "7:30 - 9:45" e una nota tra parentesi.
• PAUSA n — una sosta: orario, nome del luogo, eventuale link.
• ARRIVO — destinazione finale.
• PER TORNARE: … — testo libero come nota finale.

I link maps.app.goo.gl vengono risolti automaticamente. Le coordinate "lat,lon" sono supportate."""

private const val example = """Percorso intero V3
Carcare - Borgo San Dalmazzo

TAPPA 1
Carcare - Colle della Maddalena
2h 15' 148Km
7:30 - 9:45

PAUSA 1
9:45 - 10:30
Colle della Maddalena

ARRIVO
18:15
Borgo San Dalmazzo"""
