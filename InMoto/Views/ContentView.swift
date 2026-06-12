import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ImportedRoutesView()
                .tabItem { Label("Bikers Liguria Roadtrip", systemImage: "map.fill") }
                .tag(0)
            MoreView()
                .tabItem { Label("Altro", systemImage: "ellipsis.circle") }
                .tag(1)
        }
        .tint(.indigo)
    }
}
