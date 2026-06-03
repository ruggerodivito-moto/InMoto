import Foundation

class APIService {
    static let shared = APIService()
    private init() {}

    func composeRoute(_ body: ComposeRequest) async throws -> MotoRoute {
        let settings = AppSettings.shared
        let url = settings.apiURL("/api/mobile/moto/compose")
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.apiKey, forHTTPHeaderField: "X-Moto-Key")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try JSONDecoder().decode(ComposeResponse.self, from: data)
        guard result.ok, let route = result.route else {
            throw APIError.serverError(result.error ?? "Errore sconosciuto")
        }
        return route
    }

    enum APIError: LocalizedError {
        case serverError(String)
        var errorDescription: String? {
            if case .serverError(let msg) = self { return msg }
            return nil
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }

    var isConfigured: Bool { !serverURL.isEmpty && !apiKey.isEmpty }

    func apiURL(_ path: String) -> URL {
        URL(string: serverURL.trimmingCharacters(in: .init(charactersIn: "/")) + path)!
    }

    private init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        apiKey    = UserDefaults.standard.string(forKey: "apiKey")    ?? ""
    }
}
