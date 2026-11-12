import SwiftUI
import Charts
import HistoryKit

/// The Progress tab: consistency over recent weeks, each exercise, and every session.
public struct ProgressScreen: View {
    @State private var viewModel: ProgressViewModel

    public init(viewModel: ProgressViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    enum Route: Hashable {
        case exercise(UUID)
        case session(UUID)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ProgressMasthead()
                    if viewModel.hasSessions {
                        statement.padding(.top, 24)
                        ConsistencyChart(weeks: viewModel.weeks).padding(.top, 20)
                        exercisesSection.padding(.top, 32)
                        historySection.padding(.top, 32)
                    } else {
                        emptyState.padding(.top, 40)
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.s(3))
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
                }
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

    private var statement: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Last \(ProgressViewModel.weeksShown) weeks")
            Text(viewModel.activeDays == 1 ? "1 active day" : "\(viewModel.activeDays) active days")
                .font(AppFont.display(42, weight: .bold))
                .tracking(-1.6)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.streak > 1 {
                Text("\(viewModel.streak)-DAY STREAK")
                    .font(AppFont.mono(11, weight: .medium))
                    .tracking(0.7)
            }
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            SectionLabel("01 — Exercises").padding(.top, 10).padding(.bottom, 4)
            ForEach(viewModel.exercises) { row in
                NavigationLink(value: Route.exercise(row.id)) {
                    ExerciseProgressRow(row: row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            SectionLabel("02 — History").padding(.top, 10)
            ForEach(viewModel.months) { month in
                Text(month.title.uppercased())
                    .font(AppFont.mono(11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(month.sessions) { session in
                    NavigationLink(value: Route.session(session.id)) {
                        SessionHistoryRow(row: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sessions yet")
                .font(AppFont.display(36, weight: .bold))
                .tracking(-1.4)
            Text("Finish a session, or log one from Today, and your history shows up here.")
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
        }
    }
}

private struct ProgressMasthead: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress")
                .font(AppFont.display(22, weight: .heavy))
                .tracking(-0.9)
                .frame(minHeight: 44)
                .accessibilityAddTraits(.isHeader)
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }
}

/// Active days per week, this week in the accent.
private struct ConsistencyChart: View {
    let weeks: [WeekCount]
    @Environment(\.appAccent) private var accent

    var body: some View {
        Chart(weeks) { week in
            BarMark(
                x: .value("Week", week.weekStart, unit: .weekOfYear),
                y: .value("Active days", week.days)
            )
            .foregroundStyle(week.id == weeks.last?.id ? accent : AppColor.ink)
        }
        .chartYScale(domain: 0...7)
        .chartYAxis {
            AxisMarks(values: [0, 7]) { _ in
                AxisGridLine().foregroundStyle(AppColor.hairline)
                AxisValueLabel().font(AppFont.mono(10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    .font(AppFont.mono(9))
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let thisWeek = weeks.last?.days ?? 0
        let average = weeks.isEmpty ? 0 : Double(weeks.reduce(0) { $0 + $1.days }) / Double(weeks.count)
        return "Active days per week. This week \(thisWeek). Average \(average.formatted(.number.precision(.fractionLength(1)))) over \(weeks.count) weeks."
    }
}

private struct ExerciseProgressRow: View {
    let row: ProgressViewModel.ExerciseRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(AppFont.display(17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(AppFont.mono(11))
                    .tracking(0.4)
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Spacer(minLength: 8)
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

    private var detail: String {
        let done = row.stats.completed == 1 ? "DONE 1×" : "DONE \(row.stats.completed)×"
        guard let last = row.stats.lastDone else { return "NOT DONE YET" }
        return "\(done) — LAST \(last.formatted(.dateTime.day().month(.abbreviated)).uppercased())"
    }
}

private struct SessionHistoryRow: View {
    let row: ProgressViewModel.SessionRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                .font(AppFont.mono(12, weight: .medium))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.isComplete ? "Complete" : "Partial")
                    .font(AppFont.display(16, weight: .medium))
                Text(detail)
                    .font(AppFont.mono(11))
                    .tracking(0.4)
                    .foregroundStyle(AppColor.inkSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let done = row.doneCount == 1 ? "1 EXERCISE" : "\(row.doneCount) EXERCISES"
        guard let minutes = row.minutes else { return "\(done) — LOGGED" }
        return "\(done) — \(minutes) MIN"
    }
}
