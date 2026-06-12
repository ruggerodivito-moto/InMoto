import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// "Altro": raccoglie tragitti personali, preferiti, guida e impostazioni
// ═════════════════════════════════════════════════════════════════════════════

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ImportedRoutesView()
                    } label: {
                        Label("Tragitti personali", systemImage: "bookmark.fill")
                    }
                    NavigationLink {
                        FavoritePlacesView()
                    } label: {
                        Label("Luoghi preferiti", systemImage: "star.fill")
                    }
                }

                Section {
                    NavigationLink {
                        GuideView()
                    } label: {
                        Label("Come aggiungere un viaggio", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Guide")
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("Altro")
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Guida: aggiungere un viaggio incollando il testo del roadbook
// ═════════════════════════════════════════════════════════════════════════════

struct GuideView: View {
    @State private var showRoadbook = false

    private let esempio = """
    Giro delle Langhe
    Alba - Barolo
    8h 10' 456Km

    TAPPA 1
    Alba - Colle della Maddalena
    (rifornimento all'Autogrill)
    https://maps.app.goo.gl/xxxxxxxx
    2h 15' 148Km
    7:30 - 9:45

    PAUSA 1
    9:45 - 10:30
    Colle della Maddalena
    https://maps.app.goo.gl/yyyyyyyy

    ARRIVO
    18:15
    Barolo
    https://maps.app.goo.gl/zzzzzzzz
    """

    var body: some View {
        List {
            // ── Cosa fa ───────────────────────────────────────────────────────
            Section {
                Text("Puoi creare un intero viaggio a tappe incollando un testo (un \u{201C}roadbook\u{201D}). L'app riconosce tappe, pause, orari, distanze e i link di Google Maps, e prepara i percorsi pronti da navigare.")
                    .font(.subheadline)
            } header: {
                Text("Aggiungere un viaggio da testo")
            }

            // ── Passi ─────────────────────────────────────────────────────────
            Section {
                guideStep(1, "Apri \u{201C}Altro\u{201D} \u{2192} \u{201C}Tragitti personali\u{201D}.")
                guideStep(2, "Tocca il \u{201C}+\u{201D} in alto a destra e scegli \u{201C}Importa roadbook (viaggio)\u{201D}.")
                guideStep(3, "Incolla il testo del viaggio nel riquadro.")
                guideStep(4, "Tocca \u{201C}Analizza roadbook\u{201D}: vedrai l'anteprima delle tappe.")
                guideStep(5, "Tocca \u{201C}Salva viaggio\u{201D}. Lo ritrovi in \u{201C}Tragitti personali\u{201D}.")
            } header: {
                Text("Passo per passo")
            }

            // ── Formato ───────────────────────────────────────────────────────
            Section {
                formatRow("TAPPA 1, TAPPA 2…", "Inizia una tratta da guidare. Sotto, il link Google Maps del percorso.")
                formatRow("PAUSA 1, PAUSA 2…", "Una sosta: nome del luogo e/o link del posto.")
                formatRow("ARRIVO", "Destinazione finale del viaggio.")
                formatRow("Link Google Maps", "Da Google Maps: Condividi \u{2192} Copia link. Vanno bene sia i link del percorso che del singolo luogo.")
                formatRow("Orari", "Es. 7:30 - 9:45 oppure 18:15.")
                formatRow("Distanza e durata", "Es. 148Km e 2h 15'.")
                formatRow("Note tra parentesi", "Es. (rifornimento): vengono conservate come nota.")
            } header: {
                Text("Cosa puoi scrivere")
            } footer: {
                Text("L'ordine delle righe dentro una sezione non conta. Servono almeno una sezione TAPPA e i suoi link perché il percorso sia navigabile.")
            }

            // ── Esempio ───────────────────────────────────────────────────────
            Section {
                Text(esempio)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("Esempio")
            } footer: {
                Text("Sostituisci i link di esempio con quelli reali copiati da Google Maps.")
            }

            // ── Scorciatoia ───────────────────────────────────────────────────
            Section {
                Button {
                    showRoadbook = true
                } label: {
                    Label("Apri importazione roadbook", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
        }
        .navigationTitle("Aggiungere un viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRoadbook) {
            RoadbookImportView()
        }
    }

    private func guideStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo).frame(width: 24, height: 24)
                Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func formatRow(_ keyword: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(keyword)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
