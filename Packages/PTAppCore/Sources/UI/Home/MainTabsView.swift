import SwiftUI
import DataKit

/// The app's two main screens.
public enum MainTab: Hashable, Sendable {
    case today, progress
}

/// Today and Progress, with one glass bar holding the tab switcher and the Start
/// button side by side, instead of a start bar stacked over the system tab bar.
public struct MainTabsView: View {
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
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: MainTab.today) {
                HomeView(viewModel: home, onStart: onStart, onSettings: onSettings,
                         onSetup: onSetup, onEditRoutine: onEditRoutine)
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom) { bar }
            }
            Tab("Progress", systemImage: "chart.bar.xaxis", value: MainTab.progress) {
                ProgressScreen(viewModel: progress)
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom) { bar }
            }
        }
    }

    private var bar: some View {
        MainBar(selection: $selection, start: home.startInfo, onStart: onStart)
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(1))
    }
}

extension HomeViewModel {
    /// What the Start button says, or nil when there's no routine to start.
    var startInfo: MainBar.StartInfo? {
        guard hasRoutine else { return nil }
        return MainBar.StartInfo(
            title: isDoneToday ? "Start again" : "Start session",
            detail: "\(rows.count) EX — \(estimatedMinutes) MIN"
        )
    }
}

/// The tab switcher and, when there's a routine, the Start button, in one row of glass.
struct MainBar: View {
    struct StartInfo: Equatable {
        let title: String
        let detail: String
    }

    @Binding var selection: MainTab
    let start: StartInfo?
    let onStart: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                tabs
                if let start {
                    startButton(start)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tab(.today, title: "Today", systemImage: "sun.max")
            tab(.progress, title: "Progress", systemImage: "chart.bar.xaxis")
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func tab(_ value: MainTab, title: String, systemImage: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(AppFont.display(11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(AppColor.ink)
            .frame(minWidth: 64, minHeight: 52)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Capsule().fill(AppColor.ink.opacity(0.1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func startButton(_ start: StartInfo) -> some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 40, height: 40)
                    .background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(start.title)
                        .font(AppFont.display(16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(start.detail)
                        .font(AppFont.mono(10))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
        }
        .buttonStyle(InkGlassButtonStyle())
        .accessibilityLabel(start.title)
        .accessibilityValue(start.detail.lowercased())
    }
}
