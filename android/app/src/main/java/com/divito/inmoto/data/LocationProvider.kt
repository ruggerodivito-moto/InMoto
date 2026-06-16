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
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Sorgente GPS basata su FusedLocationProviderClient — equivalente Android di
 * LocationManager/CoreLocation. Espone gli aggiornamenti come [Flow]; il
 * permesso di localizzazione va richiesto dal chiamante prima di collezionare.
 */
class LocationProvider(context: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(context.applicationContext)

    /**
     * Stream di posizioni ad alta precisione (~1 s). Nessun filtro sulla distanza:
     * gli aggiornamenti arrivano anche da fermo (semaforo, sosta), così la
     * navigazione parte senza dover prima muoversi. Accetta anche fix degradati
     * (fino a 150 m): in navigazione meglio un aggiornamento impreciso che nessuno
     * (gallerie, al chiuso, maltempo); il map matching tollera il rumore.
     *
     * Emette subito un "seed" iniziale (ultima posizione nota + un fix one-shot)
     * perché con PRIORITY_HIGH_ACCURACY il FusedLocationProvider può attendere il
     * lock GPS prima del primo update continuo: da fermo o al chiuso resterebbe
     * altrimenti in "attesa del GPS".
     */
    @SuppressLint("MissingPermission")
    fun locationUpdates(): Flow<Location> = callbackFlow {
        fun emit(loc: Location?) {
            if (loc != null && loc.accuracy in 0f..150f) trySend(loc)
        }

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
            .setMinUpdateIntervalMillis(500L)
            .setWaitForAccurateLocation(false)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                emit(result.lastLocation)
            }
        }

        // Seed immediato: la navigazione si aggancia subito, senza aspettare il
        // primo update continuo (che con HIGH_ACCURACY può tardare da fermo).
        client.lastLocation.addOnSuccessListener { emit(it) }
        client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null).addOnSuccessListener { emit(it) }

        client.requestLocationUpdates(request, callback, Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(callback) }
    }

    /** Un solo fix di posizione (per capire se sei già alla partenza). Null se non disponibile. */
    @SuppressLint("MissingPermission")
    suspend fun oneShot(): Location? = suspendCancellableCoroutine { cont ->
        client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
            .addOnSuccessListener { loc ->
                if (loc != null) cont.resumeWith(Result.success(loc))
                else client.lastLocation
                    .addOnSuccessListener { cont.resumeWith(Result.success(it)) }
                    .addOnFailureListener { cont.resumeWith(Result.success(null)) }
            }
            .addOnFailureListener { cont.resumeWith(Result.success(null)) }
    }
}
