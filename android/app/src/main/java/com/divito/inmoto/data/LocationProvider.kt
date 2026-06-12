package com.divito.inmoto.data

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Sorgente GPS basata su FusedLocationProviderClient — equivalente Android di
 * LocationManager/CoreLocation. Espone gli aggiornamenti come [Flow]; il
 * permesso di localizzazione va richiesto dal chiamante prima di collezionare.
 */
class LocationProvider(context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context.applicationContext)

    /**
     * Stream di posizioni ad alta precisione (~1 s / 5 m). Scarta i fix troppo
     * imprecisi (>100 m) ma accetta quelli degradati: in navigazione meglio un
     * aggiornamento impreciso che nessuno (gallerie, maltempo).
     */
    @SuppressLint("MissingPermission")
    fun locationUpdates(): Flow<Location> = callbackFlow {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
            .setMinUpdateIntervalMillis(500L)
            .setMinUpdateDistanceMeters(5f)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                if (loc.accuracy in 0f..100f) trySend(loc)
            }
        }

        client.requestLocationUpdates(request, callback, Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(callback) }
    }
}
