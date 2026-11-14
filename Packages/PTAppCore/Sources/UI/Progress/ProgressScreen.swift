import SwiftUI
import HistoryKit

/// The Progress tab: the weekly goal, consistency, pain, how exercises felt, what's
/// worth telling your PT, each exercise, and a way into every session.
public struct ProgressScreen: View {
    @State private var viewModel: ProgressViewModel
    @State private var preparingVisit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: ProgressViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    enum Route: Hashable {
        case exercise(UUID)
        case session(UUID)
        case allSessions
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ProgressMasthead(range: $viewModel.range, showsRange: viewModel.hasSessions)
                    if viewModel.hasSessions {
                        content
                    } else {
                        emptyState.padding(.top, 40)
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(3))
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: viewModel.range)
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: viewModel.weeklyGoal)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.surface.ignoresSafeArea())
            .foregroundStyle(AppColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .exercise(let id):
                    ExerciseProgressView(viewModel: viewModel, exerciseID: id)
                case .session(let id):
                    SessionDetailView(viewModel: viewModel, sessionID: id)
                case .allSessions:
                    AllSessionsView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $preparingVisit) {
                VisitSummaryView(summary: viewModel.visitSummary(), rangeTitle: viewModel.range.spokenTitle)
            }
            .onAppear { viewModel.refresh() }
            .alert("Something went wrong",
                   isPresented: Binding(get: { viewModel.errorMessage != nil },
                                        set: { if !$0 { viewModel.dismissError() } }),
                   presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            GoalHeadline(viewModel: viewModel).padding(.top, 24)
            figures.padding(.top, 24)
            consistency.padding(.top, 32)
            pain.padding(.top, 32)
            feel.padding(.top, 32)
            worthTelling.padding(.top, 32)
            exercises.padding(.top, 32)
            allSessions.padding(.top, 32)
        }
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressFigure(
                value: viewModel.goalShare.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                label: "Of goal, \(viewModel.range.spokenTitle)"
            )
            ProgressFigure(value: "\(viewModel.minutes)", label: "Minutes")
            ProgressFigure(value: viewModel.painNow.map(String.init) ?? "—", label: "Pain now",
                           detail: painDetail)
        }
        .overlay(alignment: .top) { InkRule() }
    }

    private var painDetail: String? {
        guard let now = viewModel.painNow, let from = viewModel.painFrom else { return nil }
        return now < from ? "↓ from \(from)" : "↑ from \(from)"
    }

    private var consistency: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "01 — Consistency", trailing: "\(viewModel.heatmap.count) weeks")
            ConsistencyHeatmap(weeks: viewModel.heatmap)
            HStack(spacing: 14) {
                legendSwatch("Done", opacity: 1)
                legendSwatch("Partial", opacity: 0.35)
                Spacer()
                if viewModel.longestStreak > 1 {
                    Text("LONGEST STREAK \(viewModel.longestStreak) DAYS")
                        .font(AppFont.mono(10, weight: .medium))
                        .tracking(0.5)
                }
            }
            .padding(.top, 12)
        }
    }

    private func legendSwatch(_ title: String, opacity: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AccentFill(opacity: opacity))
                .frame(width: 10, height: 10)
            Text(title.uppercased())
                .font(AppFont.mono(10))
                .tracking(0.5)
                .foregroundStyle(AppColor.inkSecondary)
        }
        .accessibilityHidden(true)
    }

    private var pain: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "02 — Pain after sessions", trailing: "0–10")
            if viewModel.painPoints.isEmpty {
                hint("Record pain at the end of a session and it shows up here.")
            } else {
                PainChart(points: viewModel.painPoints)
            }
        }
    }

    private var feel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "03 — How it felt", trailing: "By week")
            if viewModel.ratingWeeks.allSatisfy({ $0.total == 0 }) {
                hint("Rate exercises during or after a session to see how they're feeling over time.")
            } else {
                RatingsChart(weeks: viewModel.ratingWeeks)
                RatingLegend().padding(.top, 12)
            }
        }
    }

    private var worthTelling: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(
                title: "04 — Worth telling your PT",
                trailing: viewModel.insights.isEmpty ? nil
                    : "\(viewModel.insights.count) \(viewModel.insights.count == 1 ? "note" : "notes")"
            )
            if viewModel.insights.isEmpty {
                hint("Nothing stands out right now. Ratings, skips and pain changes show up here when they do.")
            }
            ForEach(viewModel.insights) { insight in
                if let id = insight.exerciseID {
                    NavigationLink(value: Route.exercise(id)) { InsightCard(insight: insight) }
                        .buttonStyle(.plain)
                } else {
                    InsightCard(insight: insight)
                }
            }
            Button {
                preparingVisit = true
            } label: {
                HStack {
                    Text("Prepare for your visit")
                    Spacer()
                    Image(systemName: "doc.text")
                }
                .font(AppFont.display(17, weight: .semibold))
                .padding(.horizontal, 22)
            }
            .buttonStyle(InkGlassButtonStyle())
            .padding(.top, 16)
        }
    }

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressSectionHeader(title: "05 — Exercises", trailing: "Last \(ProgressViewModel.recentCount) times")
            ForEach(viewModel.exercises) { row in
                NavigationLink(value: Route.exercise(row.id)) {
                    ExerciseProgressRow(row: row)
                }
                .buttonStyle(.plain)
            }
            RatingLegend(showsMarks: true).padding(.top, 14)
        }
    }

    private var allSessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            NavigationLink(value: Route.allSessions) {
                HStack(alignment: .firstTextBaseline) {
                    Text("06 — All sessions")
                        .font(AppFont.display(17, weight: .medium))
                    Spacer()
                    Text("\(viewModel.sessionCount)")
                        .font(AppFont.mono(13, weight: .medium))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.inkSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All sessions, \(viewModel.sessionCount)")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body(15))
            .foregroundStyle(AppColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sessions yet")
                .font(AppFont.display(36, weight: .bold))
                .tracking(-1.4)
            Text("Finish a session, or log one from Today, and your progress shows up here.")
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
        }
    }
}

/// The accent at some strength, as a fill.
private struct AccentFill: ShapeStyle {
    let opacity: Double

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.appAccent.opacity(opacity)
    }
}

private struct ProgressMasthead: View {
    @Binding var range: ProgressRange
    let showsRange: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress")
                    .font(AppFont.display(22, weight: .heavy))
                    .tracking(-0.9)
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if showsRange {
                    Picker("Range", selection: $range) {
                        ForEach(ProgressRange.allCases) { range in
                            Text(range.title).tag(range).accessibilityLabel(range.spokenTitle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }
}

/// This week against the goal, which can be changed right here.
private struct GoalHeadline: View {
    @Bindable var viewModel: ProgressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            goalMenu
            Text("\(viewModel.daysThisWeek) of \(viewModel.weeklyGoal) days.")
                .font(AppFont.display(42, weight: .bold))
                .tracking(-1.6)
                .contentTransition(.numericText())
            Text(status)
                .font(AppFont.display(42, weight: .bold))
                .tracking(-1.6)
                .foregroundStyle(AppColor.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var goalMenu: some View {
        Menu {
            Picker("Weekly goal", selection: $viewModel.weeklyGoal) {
                ForEach(1...7, id: \.self) { days in
                    Text(days == 1 ? "1 day a week" : "\(days) days a week").tag(days)
                }
            }
        } label: {
            HStack(spacing: 4) {
                SectionLabel("This week — goal \(viewModel.weeklyGoal) days")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.inkSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Weekly goal, \(viewModel.weeklyGoal) days")
        .accessibilityHint("Changes how many days a week you aim for")
    }

    private var status: String {
        switch viewModel.goalStatus {
        case .met: "Goal met."
        case .onTrack: "On track."
        case .behind(let remaining): "\(remaining) to go."
        }
    }
}

private struct ExerciseProgressRow: View {
    let row: ProgressViewModel.ExerciseRow
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(AppFont.display(17, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let trend = row.trend { flag(trend) }
                }
                Text(detail)
                    .font(AppFont.mono(11))
                    .tracking(0.4)
                    .foregroundStyle(AppColor.inkSecondary)
                if !row.recent.isEmpty {
                    MarkStrip(marks: row.recent).padding(.top, 2)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }

    private func flag(_ trend: ExerciseTrend) -> some View {
        let loud: Bool = switch trend {
        case .harder, .painful: true
        case .oftenSkipped, .easier: false
        }
        return Text(ProgressViewModel.flag(for: trend).uppercased())
            .font(AppFont.mono(10, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(loud ? AppColor.onAccent : AppColor.inkSecondary)
            .padding(.horizontal, loud ? 6 : 0)
            .padding(.vertical, 2)
            .background(loud ? accent : .clear)
    }

    private var detail: String {
        let done = row.stats.completed == 1 ? "DONE 1×" : "DONE \(row.stats.completed)×"
        guard row.stats.lastDone != nil else { return "\(row.prescription) — NOT DONE YET" }
        return "\(row.prescription) — \(done)"
    }
}
