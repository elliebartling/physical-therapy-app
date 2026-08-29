import SwiftUI
import SwiftData

@main
struct MendApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Routine.self, Exercise.self, SessionLog.self, ExerciseLog.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        PhoneConnectivity.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "figure.strengthtraining.functional") {
                TodayView()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis") {
                TrendsView()
            }
            Tab("Routines", systemImage: "list.bullet.rectangle") {
                RoutineListView()
            }
        }
    }
}
