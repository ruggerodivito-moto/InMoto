package com.divito.inmoto.data

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.divito.inmoto.R
import java.util.concurrent.atomic.AtomicInteger

/**
 * Notifiche locali degli eventi di navigazione. Android le inoltra
 * automaticamente all'orologio Wear OS abbinato (bridging attivo di default),
 * equivalente del mirroring iOS → Apple Watch.
 */
object NavNotifier {

    private const val CHANNEL_ID = "navigation"
    private val idGen = AtomicInteger(2000)

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java) ?: return
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "Navigazione", NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "Eventi di navigazione (tappe, arrivo, fuori percorso)" }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun post(context: Context, title: String, body: String) {
        val ctx = context.applicationContext
        ensureChannel(ctx)
        val manager = NotificationManagerCompat.from(ctx)
        if (!manager.areNotificationsEnabled()) return   // permesso non concesso
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(idGen.incrementAndGet(), notif) }
    }
}
