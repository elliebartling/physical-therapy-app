import SwiftUI
import SwiftData
import DataKit
import HistoryKit

public struct HomeView: View {
    @Bindable public var viewModel: HomeViewModel
    public var onStart: () -> Void
    public var onSettings: () -> Void
    public var onSetup: () -> Void
    public var onEditRoutine: () -> Void
    @State private var logDay: LogDay? = nil

    public init(viewModel: HomeViewModel, onStart: @escaping () -> Void,
                onSettings: @escaping () -> Void, onSetup: @escaping () -> Void,
                onEditRoutine: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onStart = onStart
        self.onSettings = onSettings
        self.onSetup = onSetup
        self.onEditRoutine = onEditRoutine
    }

    public var body: some View {
        Group {
            if viewModel.hasRoutine {
                todayContent
            } else {
                emptyContent
            }
        }
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .task { await viewModel.refresh() }
        .sheet(item: $logDay, onDismiss: { Task { await viewModel.refresh() } }) { day in
            if let log = viewModel.logSession(on: day.date) {
                LogSessionView(viewModel: log) { logDay = nil }
            }
        }
    }

    private var todayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Masthead(onSettings: onSettings)
                statement.padding(.top, 24)
                WeekStripView(week: viewModel.week) { logDay = LogDay(date: $0) }
                    .padding(.top, 20)
                logSessionButton.padding(.top, 4)
                routineSection.padding(.top, 28)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(3))
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            StartSessionBar(
                title: viewModel.isDoneToday ? "Start again" : "Start session",
                detail: "\(viewModel.rows.count) EX — \(viewModel.estimatedMinutes) MIN",
                action: onStart
            )
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(1))
        }
    }

    private var statement: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("This week")
            Text(viewModel.headline)
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

    private var logSessionButton: some View {
        HStack {
            Spacer()
            Button {
                logDay = LogDay(date: .now)
            } label: {
                Label("Log a session", systemImage: "plus.circle")
                    .font(AppFont.display(15, weight: .medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Record a session you did without the app")
        }
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRule()
            HStack {
                SectionLabel("01 — Today")
                Spacer()
                SectionLabel("\(viewModel.rows.count) ex / \(viewModel.estimatedMinutes) min")
            }
            .padding(.top, 10)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(viewModel.routineName)
                    .font(AppFont.display(28, weight: .bold))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onEditRoutine) {
                    Label("Edit", systemImage: "pencil")
                        .font(AppFont.display(15, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit routine")
            }
            .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    ExerciseRowView(row: row)
                }
            }
            .padding(.top, 12)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Masthead(onSettings: onSettings)
            Spacer()
            SectionLabel("Get started")
            Text("No routine yet")
                .font(AppFont.display(44, weight: .bold))
                .tracking(-1.8)
                .padding(.top, 10)
            Text("Snap your PT handout and Mend turns it into a guided routine, read entirely on this iPhone.")
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
                .padding(.top, 12)
            Spacer()
            Button(action: onSetup) {
                HStack {
                    Text("Set up your routine")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(AppFont.display(17, weight: .semibold))
                .padding(.horizontal, 22)
            }
            .buttonStyle(InkGlassButtonStyle())
            .padding(.bottom, AppSpacing.s(1))
        }
        .padding(.horizontal, AppSpacing.screenPadding)
    }
}

private struct Masthead: View {
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("Mend")
                    .font(AppFont.display(22, weight: .heavy))
                    .tracking(-0.9)
                Spacer()
                Text(Self.dateLabel(for: .now))
                    .font(AppFont.mono(11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(AppColor.inkSecondary)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .accessibilityLabel("Settings")
            }
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }

    static func dateLabel(for date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let dayMonth = date.formatted(.dateTime.day().month(.abbreviated))
        return "\(weekday) — \(dayMonth)".uppercased()
    }
}

/// Logging a session for a particular day.
struct LogDay: Identifiable {
    let date: Date
    var id: Date { date }
}

struct WeekStripView: View {
    let week: WeekStrip
    /// Called with a day on or before today. Nil makes the strip read-only.
    var onSelectDay: ((Date) -> Void)? = nil
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(week.days) { day in
                if let onSelectDay, !isFuture(day) {
                    Button { onSelectDay(day.date) } label: { column(for: day) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: day))
                        .accessibilityHint("Log a session for this day")
                } else {
                    column(for: day)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: day))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week: \(week.completedCount) of 7 days with a session")
    }

    private func column(for day: WeekStrip.Day) -> some View {
        VStack(spacing: 6) {
            cell(for: day).frame(height: 34)
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(AppFont.mono(10, weight: day.isToday ? .medium : .regular))
                .foregroundStyle(day.isToday ? AppColor.ink : AppColor.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func isFuture(_ day: WeekStrip.Day) -> Bool {
        guard let todayIndex = week.days.firstIndex(where: \.isToday),
              let index = week.days.firstIndex(of: day) else { return false }
        return index > todayIndex
    }

    private func accessibilityLabel(for day: WeekStrip.Day) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide).month().day())
        return "\(name), \(day.isCompleted ? "session done" : "no session")"
    }

    @ViewBuilder
    private func cell(for day: WeekStrip.Day) -> some View {
        if day.isCompleted {
            Rectangle().fill(AppColor.ink)
        } else if day.isToday {
            Rectangle().fill(accent)
        } else {
            Rectangle().strokeBorder(AppColor.hairline, lineWidth: 1)
        }
    }
}

private struct ExerciseRowView: View {
    let row: HomeViewModel.ExerciseRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.number)
                .font(AppFont.mono(11))
                .foregroundStyle(AppColor.inkSecondary)
                .frame(width: 30, alignment: .leading)
            Text(row.name)
                .font(AppFont.display(16, weight: .medium))
            Spacer(minLength: 12)
            Text(row.prescription)
                .font(AppFont.mono(13))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
    }
}

private struct StartSessionBar: View {
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 40, height: 40)
                    .background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppFont.display(16, weight: .semibold))
                    Text(detail)
                        .font(AppFont.mono(10))
                        .tracking(0.6)
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
        }
        .buttonStyle(InkGlassButtonStyle())
    }
}

#Preview("Home (empty)") {
    let c = try! ModelContainerFactory.inMemory()
    let vm = HomeViewModel(
        routineRepo: RoutineRepository(context: c.mainContext),
        sessionRepo: SessionRepository(context: c.mainContext)
    )
    HomeView(viewModel: vm, onStart: {}, onSettings: {}, onSetup: {})
        .modelContainer(c)
}
