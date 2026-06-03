import SwiftUI

@main
struct InMotoApp: App {
    @StateObject private var store   = RouteStore()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .onAppear { store.loadInitial() }
        }
    }
}
