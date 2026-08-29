import SwiftUI

@main
struct MendWatchApp: App {
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
        }
    }
}
