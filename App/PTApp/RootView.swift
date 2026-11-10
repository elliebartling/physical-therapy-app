import SwiftUI
import SwiftData
import DataKit
import HistoryKit
import UI

struct RootView: View {
    enum Route: Hashable { case home, setup, session, complete, settings }
    @State private var route: Route = .home
    @State private var lastStreak: Int = 0

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let routineRepo = RoutineRepository(context: modelContext)
        let sessionRepo = SessionRepository(context: modelContext)

        Group {
            switch route {
            case .home:
                HomeView(
                    viewModel: HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo),
                    onStart: { route = .session },
                    onSettings: { route = .settings },
                    onSetup: { route = .setup }
                )
            case .setup:
                SetupView(
                    viewModel: SetupViewModel(routineRepo: routineRepo),
                    onDone: { route = .home }
                )
            case .session:
                if let routine = try? routineRepo.fetchActive() {
                    SessionView(
                        viewModel: SessionViewModel(routine: routine, sessionRepo: sessionRepo),
                        onComplete: {
                            let sessions = (try? sessionRepo.fetchAll()) ?? []
                            lastStreak = StreakCalculator.currentStreak(in: sessions, today: .now)
                            route = .complete
                        }
                    )
                } else {
                    Text("No routine").onAppear { route = .home }
                }
            case .complete:
                SessionCompleteView(newStreak: lastStreak) { route = .home }
            case .settings:
                SettingsView(
                    viewModel: SettingsViewModel(),
                    onReplaceRoutine: { route = .setup }
                )
            }
        }
    }
}
