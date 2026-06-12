package com.divito.inmoto.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import java.net.URLEncoder

/** Apre un percorso/luogo in Google Maps (o browser se non installato). */
object MapsLauncher {

    /** Percorso con più tappe: prima = origine, ultima = destinazione, in mezzo waypoint. */
    fun openRoute(context: Context, waypoints: List<String>) {
        val clean = waypoints.map { it.trim() }.filter { it.isNotEmpty() }
        if (clean.isEmpty()) {
            Toast.makeText(context, "Nessuna tappa", Toast.LENGTH_SHORT).show()
            return
        }
        if (clean.size == 1) { openPlace(context, clean.first()); return }

        val origin = enc(clean.first())
        val destination = enc(clean.last())
        val mid = clean.drop(1).dropLast(1).joinToString("|") { enc(it) }
        val url = buildString {
            append("https://www.google.com/maps/dir/?api=1")
            append("&origin=").append(origin)
            append("&destination=").append(destination)
            if (mid.isNotEmpty()) append("&waypoints=").append(mid)
            append("&travelmode=driving")
        }
        launch(context, url)
    }

    fun openPlace(context: Context, query: String) {
        val url = "https://www.google.com/maps/search/?api=1&query=${enc(query)}"
        launch(context, url)
    }

    private fun launch(context: Context, url: String) {
        runCatching {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }.onFailure {
            Toast.makeText(context, "Impossibile aprire Google Maps", Toast.LENGTH_SHORT).show()
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
