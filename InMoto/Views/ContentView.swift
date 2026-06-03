import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Itinerari", systemImage: "map.fill") }
                .tag(0)
            SearchView()
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
                .tag(1)
            CreateRouteView()
                .tabItem { Label("Crea", systemImage: "arrow.triangle.swap") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.indigo)
    }
}
