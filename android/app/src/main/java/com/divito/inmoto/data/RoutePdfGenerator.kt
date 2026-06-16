package com.divito.inmoto.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.pdf.PdfDocument
import com.divito.inmoto.model.GeoPoint
import com.divito.inmoto.model.GeocodedWaypoint
import com.divito.inmoto.model.MotoRoute
import com.divito.inmoto.model.NavigationRoute
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.maplibre.android.MapLibre
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.Style
import org.maplibre.android.snapshotter.MapSnapshotter
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Genera un PDF "scheda tragitto" orizzontale (mappa grande a sinistra, dati a
 * destra). La mappa è uno snapshot MapLibre/OSM con la polyline e i marcatori
 * dei nodi. Port di RoutePDFGenerator.swift (qui PdfDocument + MapSnapshotter).
 */
object RoutePdfGenerator {

    private const val PAGE_W = 842
    private const val PAGE_H = 595
    private const val PAD = 28f

    // Pannello mappa (sinistra)
    private const val MAP_X = PAD
    private const val MAP_Y = 80f
    private const val MAP_W = 470f
    private const val MAP_H = 470f

    private val ORANGE = Color.rgb(242, 128, 18)
    private val INK = Color.rgb(31, 31, 33)
    private val FAINT = Color.rgb(118, 118, 118)

    private const val OSM_STYLE = """
    {
      "version": 8,
      "sources": { "osm": { "type": "raster", "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], "tileSize": 256 } },
      "layers": [ { "id": "osm", "type": "raster", "source": "osm" } ]
    }
    """

    suspend fun generate(context: Context, route: MotoRoute, navRoute: NavigationRoute): File? {
        val coords = navRoute.legs.flatMap { it.polylineCoordinates }
        val mapBitmap = if (coords.size >= 2)
            runCatching { snapshot(context, coords, navRoute.waypoints) }.getOrNull() else null

        return withContext(Dispatchers.Default) {
            runCatching { renderPdf(context, route, navRoute, mapBitmap) }.getOrNull()
        }
    }

    // MARK: - Snapshot mappa

    private suspend fun snapshot(context: Context, coords: List<GeoPoint>, nodes: List<GeocodedWaypoint>): Bitmap? =
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { cont ->
                MapLibre.getInstance(context)
                val bounds = boundsFor(coords)
                val wPx = (MAP_W * 2).toInt()
                val hPx = (MAP_H * 2).toInt()
                val options = MapSnapshotter.Options(wPx, hPx)
                    .withRegion(bounds)
                    .withStyleBuilder(Style.Builder().fromJson(OSM_STYLE))
                    .withLogo(false)
                val snapshotter = MapSnapshotter(context, options)
                snapshotter.start(
                    { snap ->
                        val result = runCatching { drawOverlay(snap, coords, nodes) }.getOrNull()
                        if (cont.isActive) cont.resumeWith(Result.success(result))
                    },
                    { _ ->
                        if (cont.isActive) cont.resumeWith(Result.success(null))
                    },
                )
            }
        }

    private fun boundsFor(coords: List<GeoPoint>): LatLngBounds {
        var minLat = 90.0; var maxLat = -90.0; var minLon = 180.0; var maxLon = -180.0
        for (c in coords) {
            if (c.lat < minLat) minLat = c.lat; if (c.lat > maxLat) maxLat = c.lat
            if (c.lon < minLon) minLon = c.lon; if (c.lon > maxLon) maxLon = c.lon
        }
        val padLat = ((maxLat - minLat) * 0.16).coerceAtLeast(0.0008)
        val padLon = ((maxLon - minLon) * 0.16).coerceAtLeast(0.0008)
        return LatLngBounds.from(maxLat + padLat, maxLon + padLon, minLat - padLat, minLon - padLon)
    }

    private fun drawOverlay(snap: org.maplibre.android.snapshotter.MapSnapshot,
                            coords: List<GeoPoint>, nodes: List<GeocodedWaypoint>): Bitmap {
        val bmp = snap.bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(bmp)
        val pts = coords.map { snap.pixelForLatLng(LatLng(it.lat, it.lon)) }

        val path = Path()
        pts.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
        val halo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 16f; color = Color.argb(240, 255, 255, 255)
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        canvas.drawPath(path, halo)
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 9f; color = ORANGE
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        canvas.drawPath(path, line)

        nodes.forEachIndexed { i, wp ->
            val p = snap.pixelForLatLng(LatLng(wp.latitude, wp.longitude))
            val color = when (i) { 0 -> Color.rgb(46, 155, 46); nodes.size - 1 -> Color.rgb(211, 47, 47); else -> ORANGE }
            drawNodeMarker(canvas, p.x, p.y, i + 1, color)
        }
        return bmp
    }

    private fun drawNodeMarker(canvas: Canvas, x: Float, y: Float, number: Int, color: Int) {
        val r = 26f
        val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.WHITE }
        canvas.drawCircle(x, y, r + 5, white)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawCircle(x, y, r, fill)
        val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = Color.WHITE; textSize = 30f; isFakeBoldText = true; textAlign = Paint.Align.CENTER
        }
        canvas.drawText("$number", x, y - (tp.descent() + tp.ascent()) / 2, tp)
    }

    // MARK: - PDF

    private fun renderPdf(context: Context, route: MotoRoute, navRoute: NavigationRoute, map: Bitmap?): File {
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, 1).create())
        val c = page.canvas
        c.drawColor(Color.WHITE)

        drawHeader(c, route)
        drawMapPanel(c, map)
        drawSidePanel(c, route, navRoute)

        doc.finishPage(page)
        val file = File(context.cacheDir, "${safeName(route.nome)}.pdf")
        FileOutputStream(file).use { doc.writeTo(it) }
        doc.close()
        return file
    }

    private fun drawHeader(c: Canvas, route: MotoRoute) {
        val h = 60f
        val bg = Paint().apply {
            shader = LinearGradient(0f, 0f, PAGE_W.toFloat(), 0f,
                Color.rgb(30, 30, 35), Color.rgb(56, 56, 64), Shader.TileMode.CLAMP)
        }
        c.drawRect(0f, 0f, PAGE_W.toFloat(), h, bg)
        text(c, "INMOTO", PAD, 38f, 22f, Color.WHITE, bold = true)
        text(c, "SCHEDA TRAGITTO · ${dateString()}", PAGE_W - PAD, 36f, 11f,
            Color.argb(220, 255, 255, 255), bold = true, align = Paint.Align.RIGHT)
    }

    private fun drawMapPanel(c: Canvas, map: Bitmap?) {
        val rect = RectF(MAP_X, MAP_Y, MAP_X + MAP_W, MAP_Y + MAP_H)
        if (map != null) {
            c.save()
            val clip = Path().apply { addRoundRect(rect, 16f, 16f, Path.Direction.CW) }
            c.clipPath(clip)
            c.drawBitmap(map, null, rect, Paint(Paint.FILTER_BITMAP_FLAG))
            c.restore()
        } else {
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(237, 237, 237) }
            c.drawRoundRect(rect, 16f, 16f, p)
            text(c, "Mappa non disponibile", MAP_X + MAP_W / 2, MAP_Y + MAP_H / 2, 13f, FAINT, align = Paint.Align.CENTER)
        }
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 1f; color = Color.rgb(217, 217, 217)
        }
        c.drawRoundRect(rect, 16f, 16f, border)
    }

    private fun drawSidePanel(c: Canvas, route: MotoRoute, navRoute: NavigationRoute) {
        val x = MAP_X + MAP_W + 22f
        val w = PAGE_W - x - PAD
        var y = MAP_Y + 6f

        // Titolo
        y = drawWrapped(c, route.nome, x, y, w, 20f, INK, bold = true, maxLines = 2)
        y += 6f
        text(c, "${route.transportMode.label}  ·  ${shortName(route.partenza)} → ${shortName(route.arrivo)}",
            x, y + 11f, 11f, ORANGE, bold = true)
        y += 24f

        // Statistiche 2×2
        val km = maxOf(1, (navRoute.totalDistanceMeters / 1000).roundToInt())
        val cellW = (w - 10f) / 2
        statCell(c, x, y, cellW, "$km km", "Distanza")
        statCell(c, x + cellW + 10f, y, cellW, navRoute.formattedDuration, "Durata")
        y += 52f
        statCell(c, x, y, cellW, "${navRoute.waypoints.size}", "Nodi")
        statCell(c, x + cellW + 10f, y, cellW, route.difficolta, "Difficoltà")
        y += 60f

        // Nodi
        text(c, "NODI DEL PERCORSO (${navRoute.waypoints.size})", x, y, 11f, INK, bold = true)
        y += 16f
        val maxY = MAP_Y + MAP_H
        for ((i, wp) in navRoute.waypoints.withIndex()) {
            if (y > maxY - 14f) {
                text(c, "…", x, y, 12f, FAINT); break
            }
            val color = when (i) { 0 -> Color.rgb(46, 155, 46); navRoute.waypoints.size - 1 -> Color.rgb(211, 47, 47); else -> ORANGE }
            val cy = y - 4f
            c.drawCircle(x + 11f, cy, 11f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
            val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.WHITE; textSize = 12f; isFakeBoldText = true; textAlign = Paint.Align.CENTER }
            c.drawText("${i + 1}", x + 11f, cy - (tp.descent() + tp.ascent()) / 2, tp)
            text(c, shortName(wp.name), x + 30f, y, 12.5f, INK, bold = true)
            y += 15f
            val note = wp.note
            if (!note.isNullOrBlank() && y <= maxY - 12f) {
                y = drawWrapped(c, note, x + 30f, y, w - 30f, 10.5f, FAINT, italic = true, maxLines = 2)
            }
            y += 9f
        }
    }

    private fun statCell(c: Canvas, x: Float, y: Float, w: Float, value: String, label: String) {
        val rect = RectF(x, y, x + w, y + 46f)
        c.drawRoundRect(rect, 10f, 10f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(247, 247, 247) })
        text(c, value, x + 12f, y + 24f, 16f, INK, bold = true)
        text(c, label.uppercase(), x + 12f, y + 38f, 8.5f, FAINT, bold = true)
    }

    // MARK: - Helper di disegno

    private fun text(c: Canvas, s: String, x: Float, y: Float, size: Float, color: Int,
                     bold: Boolean = false, italic: Boolean = false, align: Paint.Align = Paint.Align.LEFT) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; textSize = size; textAlign = align
            isFakeBoldText = bold; if (italic) textSkewX = -0.25f
        }
        c.drawText(s, x, y, p)
    }

    /** Disegna testo a capo entro [w], ritorna la nuova y. */
    private fun drawWrapped(c: Canvas, s: String, x: Float, y: Float, w: Float, size: Float, color: Int,
                            bold: Boolean = false, italic: Boolean = false, maxLines: Int = 3): Float {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; textSize = size; isFakeBoldText = bold; if (italic) textSkewX = -0.25f
        }
        val words = s.split(" ")
        var line = ""
        var cy = y
        var lines = 0
        for (word in words) {
            val test = if (line.isEmpty()) word else "$line $word"
            if (p.measureText(test) > w && line.isNotEmpty()) {
                c.drawText(line, x, cy, p)
                lines++; cy += size + 3f; line = word
                if (lines >= maxLines) { line = ""; break }
            } else line = test
        }
        if (line.isNotEmpty()) { c.drawText(line, x, cy, p); cy += size + 3f }
        return cy
    }

    private fun shortName(full: String): String = full.substringBefore(",").ifEmpty { full }

    private fun dateString(): String =
        SimpleDateFormat("d MMMM yyyy", Locale("it", "IT")).format(java.util.Date())

    private fun safeName(name: String): String {
        val base = name.trim().ifBlank { "Tragitto" }
        val cleaned = base.replace(Regex("[/\\\\:?%*|\"<>]"), "-")
        return "InMoto - $cleaned"
    }
}
