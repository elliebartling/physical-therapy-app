import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \SessionLog.startedAt) private var sessions: [SessionLog]
    @Query private var routines: [Routine]
    @State private var selectedExercise: String?

    private var target: Int {
        max(1, routines.first(where: \.isActive)?.daysPerWeek ?? routines.first?.daysPerWeek ?? 7)
    }

    private var sessionDates: [Date] {
        sessions.map(\.startedAt)
    }

    private var exerciseNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for log in sessions.flatMap(\.exerciseLogs) where !log.skipped {
            if seen.insert(log.name).inserted {
                names.append(log.name)
            }
        }
        return names.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if sessions.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing to chart yet", systemImage: "chart.line.uptrend.xyaxis")
                        } description: {
                            Text("Finish your first session and your compliance and progression will show up here.")
                        }
                        .padding(.top, 80)
                    } else {
                        statTiles
                        weeklyChart
                        if !exerciseNames.isEmpty {
                            progressionChart
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
        }
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        let dayStreak = ComplianceEngine.dayStreak(sessionDates: sessionDates)
        let weekStreak = ComplianceEngine.weekStreak(sessionDates: sessionDates, target: target)
        let thisWeek = ComplianceEngine.currentWeekCount(sessionDates: sessionDates)

        return HStack(spacing: 12) {
            statTile(value: "\(thisWeek)/\(target)", label: "This week")
            statTile(value: "\(dayStreak)", label: "Day streak")
            statTile(value: "\(weekStreak)", label: "Week streak")
            statTile(value: "\(sessions.count)", label: "Sessions")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Weekly compliance

    private var weeklyChart: some View {
        let stats = ComplianceEngine.weekStats(sessionDates: sessionDates, target: target, weeks: 8)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly sessions")
                    .font(.headline)
                Text("Days with a completed session, against your \(target)×/week prescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(stats) { stat in
                    BarMark(
                        x: .value("Week", stat.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", stat.sessions),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...max(7, target))
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(.caption2)
                }
            }
            .frame(height: 180)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    // MARK: - Per-exercise progression

    private var progressionChart: some View {
        let exercise = selectedExercise ?? exerciseNames.first ?? ""
        let points = progressionPoints(for: exercise)
        let isTimed = points.allSatisfy { $0.holdSeconds > 0 }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Progression")
                    .font(.headline)
                Text(isTimed ? "Total hold time per session" : "Total reps per session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Exercise", selection: Binding(
                get: { exercise },
                set: { selectedExercise = $0 }
            )) {
                ForEach(exerciseNames, id: \.self) { name in
                    Text(name)
                }
            }
            .pickerStyle(.menu)

            if points.count < 2 {
                Text("Do this exercise in a couple more sessions to see a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(isTimed ? "Seconds" : "Reps", isTimed ? point.holdSeconds : point.reps)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(isTimed ? "Seconds" : "Reps", isTimed ? point.holdSeconds : point.reps)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(40)
                }
                .frame(height: 180)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private struct ProgressionPoint: Identifiable {
        let id = UUID()
        let date: Date
        let reps: Int
        let holdSeconds: Int
    }

    private func progressionPoints(for exerciseName: String) -> [ProgressionPoint] {
        sessions.compactMap { session in
            guard let log = session.exerciseLogs.first(where: { $0.name == exerciseName && !$0.skipped }) else {
                return nil
            }
            return ProgressionPoint(
                date: session.startedAt,
                reps: log.totalReps,
                holdSeconds: log.totalHoldSeconds
            )
        }
    }
}
