import SwiftUI

/// Compone un viaggio concatenando più tragitti in sequenza.
/// I nodi in comune (l'arrivo di un tragitto che coincide con la partenza del
/// successivo) vengono uniti automaticamente; se i nodi non coincidono viene
/// calcolata la tratta di collegamento durante la preparazione del percorso.
struct ComposeTripView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var tripName = ""
    @State private var sequence: [MotoRoute] = []
    @State private var searchText = ""
    @State private var tripToNavigate: MotoRoute?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if !sequence.isEmpty {
                    sequenceSection
                    summarySection
                }
                addSection
            }
            .navigationTitle("Componi viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .fullScreenCover(item: $tripToNavigate) { trip in
                DownloadPreparationView(route: trip)
            }
            .onChange(of: sequence) { _ in saved = false }
        }
    }

    // MARK: - Sezioni

    private var nameSection: some View {
        Section {
            TextField("Es. Weekend in Appennino", text: $tripName)
                .autocorrectionDisabled()
        } header: { Text("Nome del viaggio") }
    }

    private var sequenceSection: some View {
        Section {
            ForEach(Array(sequence.enumerated()), id: \.offset) { i, r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.indigo).frame(width: 26, height: 26)
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.nome).font(.subheadline.weight(.medium))
                            Text("\(r.partenza) → \(r.arrivo)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if i < sequence.count - 1 {
                        junctionLabel(from: r, to: sequence[i + 1])
                    }
                }
            }
            .onMove { sequence.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { sequence.remove(atOffsets: $0) }
        } header: {
            HStack {
                Text("Sequenza (\(sequence.count) tragitt\(sequence.count == 1 ? "o" : "i"))")
                Spacer()
                EditButton()
            }
        } footer: {
            Text("Trascina per riordinare. L'ordine della sequenza è l'ordine di percorrenza.")
        }
    }

    @ViewBuilder
    private func junctionLabel(from a: MotoRoute, to b: MotoRoute) -> some View {
        if samePlace(a.arrivo, b.partenza) {
            Label("Nodo in comune: \(b.partenza)", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
                .padding(.leading, 36)
        } else {
            Label("Collegamento automatico: \(a.arrivo) → \(b.partenza)",
                  systemImage: "arrow.turn.down.right")
                .font(.caption2).foregroundStyle(.orange)
                .padding(.leading, 36)
        }
    }

    private var summarySection: some View {
        Section {
            let trip = buildTrip()
            HStack {
                Label("\(trip.km) km", systemImage: "road.lanes")
                Spacer()
                Label(trip.durataFormattata, systemImage: "clock")
                Spacer()
                Label("\(trip.tappe.count) tappe", systemImage: "mappin.and.ellipse")
            }
            .font(.subheadline)

            Button {
                tripToNavigate = buildTrip()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "location.north.fill")
                    Text("Avvia navigazione").fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                store.savePersonalRoute(buildTrip())
                saved = true
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: saved ? "checkmark.circle.fill" : "bookmark.fill")
                    Text(saved ? "Salvato nei tragitti personali" : "Salva come tragitto")
                    Spacer()
                }
            }
            .tint(.green)
            .disabled(saved)
        } header: { Text("Viaggio completo") }
    }

    private var addSection: some View {
        Section {
            TextField("Cerca per nome o località", text: $searchText)
                .autocorrectionDisabled()
            ForEach(filteredRoutes.prefix(30)) { r in
                Button {
                    sequence.append(r)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: r.isCustom == true ? "person.fill" : "map")
                            .foregroundStyle(r.isCustom == true ? Color.indigo : Color.orange)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.nome).font(.subheadline).foregroundStyle(.primary)
                            Text("\(r.partenza) → \(r.arrivo)\(r.km > 0 ? " · \(r.km) km" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                    }
                }
            }
        } header: {
            Text("Aggiungi tragitto")
        } footer: {
            Text("Tragitti personali e itinerari del catalogo. Puoi aggiungere lo stesso tragitto più volte (es. anelli).")
        }
    }

    private var filteredRoutes: [MotoRoute] {
        let all = store.personalRoutes + store.routes
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.nome.lowercased().contains(q) ||
            $0.partenza.lowercased().contains(q) ||
            $0.arrivo.lowercased().contains(q) ||
            $0.regione.lowercased().contains(q)
        }
    }

    // MARK: - Fusione tragitti

    private func buildTrip() -> MotoRoute {
        var tappe: [String] = []
        var gwps:  [String] = []
        var km = 0, mins = 0

        for r in sequence {
            var t = r.tappe.isEmpty ? [r.partenza, r.arrivo].filter { !$0.isEmpty } : r.tappe
            var w = r.waypointsGmaps.isEmpty ? t.map { "\($0), Italy" } : r.waypointsGmaps
            if t.count != w.count { t = w }   // allineamento prudente
            // Nodo in comune con il tragitto precedente → unisci
            // (i nodi vicini ma con nomi diversi vengono comunque fusi dopo
            // il geocoding, per prossimità di coordinate)
            if let lastW = gwps.last, let firstW = w.first, samePlace(lastW, firstW) {
                t.removeFirst()
                w.removeFirst()
            }
            tappe += t
            gwps  += w
            km    += r.km
            mins  += r.durataMin
        }

        let names = sequence.map(\.nome)
        let name = tripName.trimmingCharacters(in: .whitespaces)
        return MotoRoute(
            id: UUID().uuidString,
            nome: name.isEmpty ? names.joined(separator: " + ") : name,
            partenza: tappe.first ?? "",
            arrivo: tappe.last ?? "",
            regione: sequence.first?.regione ?? "",
            km: km, durataMin: mins,
            difficolta: "Media", stelle: 0,
            descrizione: "Viaggio composto da \(sequence.count) tragitt\(sequence.count == 1 ? "o" : "i"): \(names.joined(separator: ", ")).",
            tappe: tappe,
            waypointsGmaps: gwps,
            tags: ["personale", "viaggio"],
            fonte: "Composto", stagione: "Tutto l'anno", isCustom: true,
            legKm: nil, legMin: nil
        )
    }

    private func samePlace(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb || na.contains(nb) || nb.contains(na)
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ", italy", with: "")
            .replacingOccurrences(of: ", italia", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
