package com.divito.inmoto.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/** Helper HTTP minimale su HttpURLConnection (niente dipendenze extra). */
object Http {

    data class Response(val status: Int, val body: String, val finalUrl: String)

    suspend fun get(
        urlString: String,
        headers: Map<String, String> = emptyMap(),
        timeoutMs: Int = 30_000,
        followRedirects: Boolean = true,
    ): Response = withContext(Dispatchers.IO) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            instanceFollowRedirects = followRedirects
            setRequestProperty("User-Agent", "InMoto-Android/1.0")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        try {
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
            Response(status, body, conn.url.toString())
        } finally {
            conn.disconnect()
        }
    }

    /** Segue i redirect (anche manualmente, per i short link Google Maps) e ritorna l'URL finale. */
    suspend fun resolveFinalUrl(urlString: String, timeoutMs: Int = 10_000): String? =
        withContext(Dispatchers.IO) {
            var current = urlString
            repeat(6) {
                val conn = (URL(current).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = timeoutMs
                    readTimeout = timeoutMs
                    instanceFollowRedirects = false
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Android) InMoto")
                }
                try {
                    val code = conn.responseCode
                    if (code in 300..399) {
                        val loc = conn.getHeaderField("Location") ?: return@withContext current
                        current = if (loc.startsWith("http")) loc
                        else URL(URL(current), loc).toString()
                    } else {
                        return@withContext conn.url.toString()
                    }
                } catch (e: Exception) {
                    return@withContext null
                } finally {
                    conn.disconnect()
                }
            }
            current
        }
}
