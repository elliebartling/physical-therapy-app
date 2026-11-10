import SwiftUI
import SwiftData
import DataKit
import UI

@main
struct PTAppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(try! ModelContainerFactory.production())
    }
}
