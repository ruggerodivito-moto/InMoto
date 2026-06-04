import MapKit

/// Autocompletamento indirizzi via Apple Maps (MKLocalSearchCompleter — gratuito, nessuna API key)
final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var results: [Suggestion] = []

    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        /// Stringa completa da mettere nel campo di testo
        var fullText: String {
            subtitle.isEmpty ? title : "\(title), \(subtitle)"
        }
    }

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.address, .pointOfInterest]
        // Centra su Italia per prioritizzare risultati italiani
        c.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 42.0, longitude: 12.5),
            span:   MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 18)
        )
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    /// Aggiorna i suggerimenti per la query corrente
    func update(query: String) {
        if query.count < 2 { results = []; return }
        completer.queryFragment = query
    }

    func clear() {
        results = []
        completer.queryFragment = ""
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.prefix(6).map {
            Suggestion(title: $0.title, subtitle: $0.subtitle)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
