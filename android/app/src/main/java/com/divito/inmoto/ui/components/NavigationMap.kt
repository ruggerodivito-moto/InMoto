package com.divito.inmoto.ui.components

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.divito.inmoto.model.GeoPoint
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

/**
 * Mappa di navigazione live MapLibre/OSM. A differenza di [RouteMap] (statica,
 * fit-to-bounds) questa **segue** la posizione agganciata al percorso con camera
 * **course-up** (direzione di marcia sempre verso l'alto, tilt 45°) e disegna
 * l'icona della moto. È l'equivalente Android di MapKitView.swift.
 *
 * - [matched] è la posizione map-matched dalla [com.divito.inmoto.data.NavigationSession];
 * - [course] la rotta in gradi (0=N) per ruotare la camera;
 * - [follow] true = camera segue la moto; false = l'utente ha trascinato la mappa
 *   (il chiamante riattiva con "ricentra");
 * - [routeVersion] cambia a ogni ricalcolo fuori percorso → ridisegna la polyline.
 */
private const val NAV_OSM_STYLE = """
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

private const val SRC_ROUTE = "nav-route-src"
private const val SRC_MOTO = "nav-moto-src"
private const val LAYER_ROUTE = "nav-route-layer"
private const val LAYER_MOTO = "nav-moto-layer"
private const val IMG_MOTO = "nav-moto-icon"

@Composable
fun NavigationMap(
    polyline: List<GeoPoint>,
    matched: GeoPoint?,
    course: Double?,
    follow: Boolean,
    routeVersion: Int,
    onUserPan: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentOnUserPan by rememberUpdatedState(onUserPan)

    val mapView = remember {
        MapLibre.getInstance(context)
        MapView(context).apply { onCreate(null) }
    }
    val mapRef = remember { mutableStateOf<MapLibreMap?>(null) }
    val styleRef = remember { mutableStateOf<Style?>(null) }

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
                // Trascinamento utente → disattiva il follow (riattivabile con "ricentra").
                map.addOnCameraMoveStartedListener { reason ->
                    if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) currentOnUserPan()
                }
                map.setStyle(Style.Builder().fromJson(NAV_OSM_STYLE)) { style ->
                    style.addImage(IMG_MOTO, motoBitmap())
                    styleRef.value = style
                }
            }
            mapView
        },
        modifier = modifier,
    )

    // Polyline del percorso: ridisegnata quando lo stile è pronto o cambia la rotta.
    LaunchedEffect(styleRef.value, routeVersion, polyline) {
        val style = styleRef.value ?: return@LaunchedEffect
        drawNavRoute(style, polyline)
    }

    // Posizione + rotazione dell'icona moto.
    LaunchedEffect(styleRef.value, matched, course) {
        val style = styleRef.value ?: return@LaunchedEffect
        updateMoto(style, matched, course)
    }

    // Camera: segue la moto course-up, oppure inquadra il percorso in attesa del GPS.
    LaunchedEffect(mapRef.value, styleRef.value, matched, course, follow, routeVersion) {
        val map = mapRef.value ?: return@LaunchedEffect
        styleRef.value ?: return@LaunchedEffect
        if (follow && matched != null) {
            val cam = CameraPosition.Builder()
                .target(LatLng(matched.lat, matched.lon))
                .bearing(course ?: map.cameraPosition.bearing)
                .tilt(45.0)
                .zoom(16.5)
                .build()
            map.animateCamera(CameraUpdateFactory.newCameraPosition(cam), 700)
        } else if (matched == null) {
            fitOverview(map, polyline)
        }
    }
}

private fun drawNavRoute(style: Style, polyline: List<GeoPoint>) {
    val linePoints = polyline.map { Point.fromLngLat(it.lon, it.lat) }
    val fc = if (linePoints.size >= 2)
        FeatureCollection.fromFeature(Feature.fromGeometry(LineString.fromLngLats(linePoints)))
    else
        FeatureCollection.fromFeatures(emptyList<Feature>())

    val src = style.getSourceAs<GeoJsonSource>(SRC_ROUTE)
    if (src != null) {
        src.setGeoJson(fc)
    } else {
        style.addSource(GeoJsonSource(SRC_ROUTE, fc))
        style.addLayer(
            LineLayer(LAYER_ROUTE, SRC_ROUTE).withProperties(
                PropertyFactory.lineColor("#1565C0"),
                PropertyFactory.lineWidth(6f),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
            ),
        )
    }
}

private fun updateMoto(style: Style, matched: GeoPoint?, course: Double?) {
    val fc = if (matched == null) {
        FeatureCollection.fromFeatures(emptyList<Feature>())
    } else {
        val f = Feature.fromGeometry(Point.fromLngLat(matched.lon, matched.lat))
        f.addNumberProperty("bearing", course ?: 0.0)
        FeatureCollection.fromFeatures(listOf(f))
    }
    val src = style.getSourceAs<GeoJsonSource>(SRC_MOTO)
    if (src != null) {
        src.setGeoJson(fc)
    } else {
        style.addSource(GeoJsonSource(SRC_MOTO, fc))
        // iconRotationAlignment = MAP + camera.bearing = course → l'icona resta verso l'alto.
        style.addLayer(
            SymbolLayer(LAYER_MOTO, SRC_MOTO).withProperties(
                PropertyFactory.iconImage(IMG_MOTO),
                PropertyFactory.iconRotate(Expression.get("bearing")),
                PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP),
                PropertyFactory.iconAllowOverlap(true),
                PropertyFactory.iconIgnorePlacement(true),
                PropertyFactory.iconSize(1.0f),
            ),
        )
    }
}

private fun fitOverview(map: MapLibreMap, polyline: List<GeoPoint>) {
    val all = polyline.map { LatLng(it.lat, it.lon) }
    if (all.isEmpty()) return
    try {
        if (all.size == 1) {
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(all.first(), 13.0))
        } else {
            val builder = LatLngBounds.Builder()
            all.forEach { builder.include(it) }
            map.moveCamera(CameraUpdateFactory.newLatLngBounds(builder.build(), 100))
        }
    } catch (_: Exception) {
        map.moveCamera(CameraUpdateFactory.newLatLngZoom(all.first(), 11.0))
    }
}

/** Freccia di marcia (chevron bianco su disco blu) generata a runtime. Punta a
 * nord: ruotata via iconRotate dalla rotta. */
private fun motoBitmap(): Bitmap {
    val size = 84
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val cx = size / 2f
    val cy = size / 2f
    val r = size * 0.40f

    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF1565C0.toInt() }
    c.drawCircle(cx, cy, r, fill)
    val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = size * 0.06f
        color = 0xFFFFFFFF.toInt()
    }
    c.drawCircle(cx, cy, r, ring)

    val arrow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt() }
    val path = Path().apply {
        moveTo(cx, cy - r * 0.62f)            // punta in alto (nord)
        lineTo(cx + r * 0.52f, cy + r * 0.55f)
        lineTo(cx, cy + r * 0.22f)
        lineTo(cx - r * 0.52f, cy + r * 0.55f)
        close()
    }
    c.drawPath(path, arrow)
    return bmp
}
