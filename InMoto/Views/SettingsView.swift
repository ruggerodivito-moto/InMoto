import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: RouteStore
    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Connessione server ─────────────────────────────────────
                Section {
                    HStack {
                        Label("URL Server", systemImage: "server.rack")
                        Spacer()
                        TextField("https://mio-server.it", text: $settings.serverURL)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("API Key", systemImage: "key.fill")
                        Spacer()
                        SecureField("Incolla la chiave", text: $settings.apiKey)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Connessione al server")
                } footer: {
                    Text("L'URL del server AMT Scanner e la API key MOTO_APP_API_KEY dal file .env.")
                }

                // ── Stato connessione ──────────────────────────────────────
                Section {
                    if settings.isConfigured {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Server configurato")
                            Spacer()
                            Button("Testa") { Task { await store.syncFromServer() } }
                                .tint(.indigo)
                        }
                    } else {
                        Label("Server non configurato", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if let msg = store.syncMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let date = store.lastSyncDate {
                        Text("Ultima sync: \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Stato") }

                // ── Sync ──────────────────────────────────────────────────
                Section {
                    Button(action: { Task { await store.syncFromServer() } }) {
                        HStack {
                            Spacer()
                            if store.isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(store.isLoading ? "Sincronizzazione…" : "Sincronizza dal server")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!settings.isConfigured || store.isLoading)
                    .tint(.indigo)
                } header: { Text("Aggiornamento dati") }
                  footer: { Text("Scarica gli itinerari aggiornati dal server e li salva per l'uso offline.") }

                // ── Info dati ──────────────────────────────────────────────
                Section {
                    LabeledContent("Itinerari in memoria", value: "\(store.routes.count)")
                    LabeledContent("Regioni disponibili", value: "\(store.regions.count)")
                } header: { Text("Dati locali") }

                // ── Info app ───────────────────────────────────────────────
                Section {
                    LabeledContent("Versione", value: "1.0.0")
                    LabeledContent("Itinerari bundle", value: "196")
                    Link(destination: URL(string: "https://www.google.com/maps")!) {
                        Label("Google Maps", systemImage: "map")
                    }
                } header: { Text("Informazioni") }
            }
            .navigationTitle("Impostazioni")
        }
    }
}
