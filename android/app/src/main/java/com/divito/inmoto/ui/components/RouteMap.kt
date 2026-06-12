package com.divito.inmoto.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.divito.inmoto.model.GeoPoint
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

/**
 * Mappa MapLibre con tile OpenStreetMap (nessuna API key). Disegna la polyline
 * del percorso e i pin dei waypoint, e centra la camera sull'estensione del
 * tracciato. È il rendering reale che sostituisce il vecchio placeholder.
 *
 * Lo stile è un raster JSON inline che punta ai tile pubblici OSM.
 */
private const val OSM_STYLE = """
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors"
    }
  },
  "layers": [
    { "id": "osm", "type": "raster", "source": "osm" }
  ]
}
"""

private const val SRC_ROUTE = "inmoto-route-src"
private const val SRC_WAYPOINTS = "inmoto-wp-src"
private const val LAYER_ROUTE = "inmoto-route-layer"
private const val LAYER_WAYPOINTS = "inmoto-wp-layer"

@Composable
fun RouteMap(
    polyline: List<GeoPoint>,
    waypoints: List<GeoPoint>,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val mapView = remember {
        MapLibre.getInstance(context)
        MapView(context).apply { onCreate(null) }
    }
    val mapRef = remember { mutableStateOf<MapLibreMap?>(null) }
    val styleRef = remember { mutableStateOf<Style?>(null) }

    // Inoltra gli eventi di ciclo di vita al MapView (richiesto da MapLibre).
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView.onPause()
            mapView.onStop()
            mapView.onDestroy()
        }
    }

    AndroidView(
        factory = {
            mapView.getMapAsync { map ->
                mapRef.value = map
                map.setStyle(Style.Builder().fromJson(OSM_STYLE)) { style ->
                    styleRef.value = style
                }
            }
            mapView
        },
        modifier = modifier,
    )

    // (Ri)disegna quando lo stile è pronto o cambiano i dati del percorso.
    LaunchedEffect(styleRef.value, polyline, waypoints) {
        val style = styleRef.value ?: return@LaunchedEffect
        val map = mapRef.value ?: return@LaunchedEffect
        drawRoute(style, polyline, waypoints)
        fitCamera(map, polyline, waypoints)
    }
}

private fun drawRoute(style: Style, polyline: List<GeoPoint>, waypoints: List<GeoPoint>) {
    // Polyline del percorso.
    val linePoints = polyline.map { Point.fromLngLat(it.lon, it.lat) }
    val lineFc = if (linePoints.size >= 2)
        FeatureCollection.fromFeature(Feature.fromGeometry(LineString.fromLngLats(linePoints)))
    else
        FeatureCollection.fromFeatures(emptyList<Feature>())

    val routeSource = style.getSourceAs<GeoJsonSource>(SRC_ROUTE)
    if (routeSource != null) {
        routeSource.setGeoJson(lineFc)
    } else {
        style.addSource(GeoJsonSource(SRC_ROUTE, lineFc))
        style.addLayer(
            LineLayer(LAYER_ROUTE, SRC_ROUTE).withProperties(
                PropertyFactory.lineColor("#1565C0"),
                PropertyFactory.lineWidth(5f),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
            ),
        )
    }

    // Pin dei waypoint.
    val wpFc = FeatureCollection.fromFeatures(
        waypoints.map { Feature.fromGeometry(Point.fromLngLat(it.lon, it.lat)) },
    )
    val wpSource = style.getSourceAs<GeoJsonSource>(SRC_WAYPOINTS)
    if (wpSource != null) {
        wpSource.setGeoJson(wpFc)
    } else {
        style.addSource(GeoJsonSource(SRC_WAYPOINTS, wpFc))
        style.addLayer(
            CircleLayer(LAYER_WAYPOINTS, SRC_WAYPOINTS).withProperties(
                PropertyFactory.circleRadius(6f),
                PropertyFactory.circleColor("#D32F2F"),
                PropertyFactory.circleStrokeWidth(2f),
                PropertyFactory.circleStrokeColor("#FFFFFF"),
            ),
        )
    }
}

private fun fitCamera(map: MapLibreMap, polyline: List<GeoPoint>, waypoints: List<GeoPoint>) {
    val all = (polyline + waypoints).map { LatLng(it.lat, it.lon) }
    if (all.isEmpty()) return
    try {
        if (all.size == 1) {
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(all.first(), 12.0))
        } else {
            val builder = LatLngBounds.Builder()
            all.forEach { builder.include(it) }
            map.moveCamera(CameraUpdateFactory.newLatLngBounds(builder.build(), 80))
        }
    } catch (_: Exception) {
        map.moveCamera(CameraUpdateFactory.newLatLngZoom(all.first(), 10.0))
    }
}
