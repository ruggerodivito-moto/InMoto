import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Itinerari", systemImage: "map.fill")
                }
            SearchView()
                .tabItem {
                    Label("Cerca", systemImage: "magnifyingglass")
                }
            SettingsView()
                .tabItem {
                    Label("Impostazioni", systemImage: "gearshape.fill")
                }
        }
        .tint(.indigo)
    }
}
