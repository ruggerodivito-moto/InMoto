package com.divito.inmoto.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.NavController
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.ui.Routes

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreScreen(vm: AppViewModel, nav: NavController) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("Altro", fontWeight = FontWeight.Bold) }) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            item {
                MenuRow(Icons.Filled.Explore, "Viaggi Personali", "Sfoglia i 196 itinerari per regione") {
                    nav.navigate(Routes.HOME_BROWSE)
                }
                HorizontalDivider()
                MenuRow(Icons.Filled.Favorite, "Luoghi preferiti", "Casa, lavoro e altri posti salvati") {
                    nav.navigate(Routes.FAVORITES)
                }
                HorizontalDivider()
                MenuRow(Icons.Filled.Info, "Come aggiungere un viaggio", "Guida al formato roadbook") {
                    nav.navigate(Routes.GUIDE)
                }
                HorizontalDivider()
                MenuRow(Icons.Filled.Settings, "Impostazioni", "Server di sincronizzazione e versione") {
                    nav.navigate(Routes.SETTINGS)
                }
            }
        }
    }
}

@Composable
private fun MenuRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title, fontWeight = FontWeight.SemiBold) },
        supportingContent = { Text(subtitle) },
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) },
        modifier = Modifier.clickable(onClick = onClick),
    )
}
