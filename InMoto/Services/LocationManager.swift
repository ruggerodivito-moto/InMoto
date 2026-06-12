import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var heading: CLHeading?

    private let manager = CLLocationManager()
    private var pendingStart = false   // start() richiesto prima del permesso

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5          // aggiorna ogni 5 metri
        manager.headingFilter = 5           // aggiorna ogni 5 gradi
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    /// Richiede un singolo fix di posizione, senza avviare la navigazione
    /// continua: serve per confronti una tantum (es. "sono al punto di partenza?")
    func requestOneShot() {
        manager.requestLocation()
    }

    func start() {
        pendingStart = true
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        pendingStart = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Accetta anche fix degradati (fino a 100 m): in navigazione è meglio un
        // aggiornamento impreciso che nessun aggiornamento (gallerie, maltempo)
        guard let loc = locations.last,
              loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        location = loc
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // Riavvia il GPS solo se una schermata lo aveva già richiesto:
        // il permesso da solo non deve accendere la localizzazione
        if pendingStart,
           manager.authorizationStatus == .authorizedAlways ||
           manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // ignora errori transitori (es. kCLErrorLocationUnknown all'avvio)
    }
}
