package com.divito.inmoto.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.divito.inmoto.AppViewModel
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.NavigationRoute

/**
 * Anteprima di un itinerario/tappa su mappa reale (MapLibre/OSM). Costruisce in
 * background il [NavigationRoute] (geocoding + routing OSRM, con cache su disco)
 * e disegna polyline + pin con [RouteMap]. Finché il percorso non è pronto, o se
 * il calcolo fallisce (es. offline), mostra un placeholder.
 */
@Composable
fun RoutePreviewMap(route: MotoRoute, vm: AppViewModel, modifier: Modifier = Modifier) {
    var nav by remember(route.id) { mutableStateOf<NavigationRoute?>(null) }
    var failed by remember(route.id) { mutableStateOf(false) }

    LaunchedEffect(route.id) {
        nav = null
        failed = false
        nav = runCatching { vm.buildNavigationRoute(route) }.getOrElse { failed = true; null }
    }

    val n = nav
    when {
        n != null -> RouteMap(
            polyline = n.legs.flatMap { it.polylineCoordinates },
            waypoints = n.waypoints.map { it.point },
            modifier = modifier,
        )
        failed -> MapPlaceholder("Mappa non disponibile", modifier)
        else -> MapPlaceholder("Caricamento mappa…", modifier, loading = true)
    }
}

@Composable
private fun MapPlaceholder(text: String, modifier: Modifier, loading: Boolean = false) {
    Surface(
        modifier = modifier.clip(RoundedCornerShape(16.dp)),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (loading) CircularProgressIndicator()
                else Icon(Icons.Filled.Map, null, tint = MaterialTheme.colorScheme.primary)
                Text(
                    text,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(12.dp),
                )
            }
        }
    }
}
