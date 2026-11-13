import SwiftUI
import SwiftData
import DataKit
import HistoryKit
import UI

struct RootView: View {
    enum Route: Hashable { case home, setup, editRoutine, session, complete, settings }
    @State private var route: Route = .home
    @State private var tab: MainTab = .today
    @State private var lastStreak: Int = 0
    @State private var finishedSession: SessionRecord?

    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.signal.rawValue
    @Environment(\.modelContext) private var modelContext

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .signal).color }

    var body: some View {
        let routineRepo = RoutineRepository(context: modelContext)
        let sessionRepo = SessionRepository(context: modelContext)

        Group {
            switch route {
            case .home:
                MainTabsView(
                    selection: $tab,
                    routineRepo: routineRepo, sessionRepo: sessionRepo,
                    onStart: { route = .session },
                    onSettings: { route = .settings },
                    onSetup: { route = .setup },
                    onEditRoutine: { route = .editRoutine }
                )
            case .editRoutine:
                if let routine = try? routineRepo.fetchActive() {
                    EditRoutineView(routine: routine, repo: routineRepo, onDone: { route = .home })
                } else {
                    Text("No routine").onAppear { route = .home }
                }
            case .setup:
                SetupView(
                    viewModel: SetupViewModel(routineRepo: routineRepo),
                    onDone: { route = .home },
                    onCancel: { route = .home }
                )
            case .session:
                if let routine = try? routineRepo.fetchActive() {
                    SessionView(
                        viewModel: SessionViewModel(routine: routine, sessionRepo: sessionRepo),
                        onComplete: { record in
                            finishedSession = record
                            let sessions = (try? sessionRepo.fetchAll()) ?? []
                            lastStreak = StreakCalculator.currentStreak(in: sessions, today: .now)
                            route = .complete
                        },
                        onEnd: { route = .home }
                    )
                } else {
                    Text("No routine").onAppear { route = .home }
                }
            case .complete:
                SessionCompleteView(
                    newStreak: lastStreak,
                    summary: finishedSession.map {
                        SessionSummaryViewModel(record: $0, routine: try? routineRepo.fetchActive(),
                                                sessionRepo: sessionRepo)
                    },
                    onDone: {
                        finishedSession = nil
                        route = .home
                    }
                )
            case .settings:
                SettingsView(
                    viewModel: SettingsViewModel(),
                    onReplaceRoutine: { route = .setup },
                    onDone: { route = .home }
                )
            }
        }
        .environment(\.appAccent, accent)
        .tint(AppColor.ink)
    }
}
