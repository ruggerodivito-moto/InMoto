import SwiftUI

class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
}

@main
struct InMotoApp: App {
    @StateObject private var store    = RouteStore()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(appState)
                .onAppear { store.loadInitial() }
        }
    }
}
