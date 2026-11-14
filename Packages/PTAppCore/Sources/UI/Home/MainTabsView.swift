import SwiftUI
import DataKit

/// The app's two main screens.
public enum MainTab: Hashable, Sendable {
    case today, progress
}

/// Today and Progress in the system tab bar, with Start as the separate round
/// button at its trailing edge. Choosing Start opens a session rather than a screen,
/// so the tab bar never stays on it.
public struct MainTabsView: View {
    /// What the tab bar can select: a screen, or Start.
    enum Slot: Hashable {
        case screen(MainTab)
        case start
    }

    @Binding private var selection: MainTab
    // Kept for the life of the view, so switching tabs doesn't rebuild either screen.
    @State private var home: HomeViewModel
    @State private var progress: ProgressViewModel
    private let onStart: () -> Void
    private let onSettings: () -> Void
    private let onSetup: () -> Void
    private let onEditRoutine: () -> Void

    public init(selection: Binding<MainTab>,
                routineRepo: RoutineRepository, sessionRepo: SessionRepository,
                onStart: @escaping () -> Void, onSettings: @escaping () -> Void,
                onSetup: @escaping () -> Void, onEditRoutine: @escaping () -> Void) {
        _selection = selection
        _home = State(initialValue: HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo))
        _progress = State(initialValue: ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo))
        self.onStart = onStart
        self.onSettings = onSettings
        self.onSetup = onSetup
        self.onEditRoutine = onEditRoutine
    }

    public var body: some View {
        TabView(selection: slot) {
            Tab("Today", systemImage: "sun.max", value: Slot.screen(.today)) {
                HomeView(viewModel: home, onStart: onStart, onSettings: onSettings,
                         onSetup: onSetup, onEditRoutine: onEditRoutine)
            }
            Tab("Progress", systemImage: "chart.bar.xaxis", value: Slot.screen(.progress)) {
                ProgressScreen(viewModel: progress)
            }
            if let start = home.startInfo {
                // The search role gives Start the tab bar's separate trailing button.
                Tab(start.title, systemImage: "play.fill", value: Slot.start, role: .search) {
                    Color.clear
                }
            }
        }
        .tint(AppColor.ink)
    }

    /// Selecting Start runs `onStart` and leaves the current screen selected.
    private var slot: Binding<Slot> {
        Binding(
            get: { .screen(selection) },
            set: { Self.route($0, selection: &selection, onStart: onStart) }
        )
    }

    static func route(_ slot: Slot, selection: inout MainTab, onStart: () -> Void) {
        switch slot {
        case .screen(let tab): selection = tab
        case .start: onStart()
        }
    }
}

/// What the Start tab says.
struct StartInfo: Equatable {
    let title: String
}

extension HomeViewModel {
    /// What the Start tab says, or nil when there's no routine to start.
    var startInfo: StartInfo? {
        guard hasRoutine else { return nil }
        return StartInfo(title: isDoneToday ? "Start again" : "Start session")
    }
}
