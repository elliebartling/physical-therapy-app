import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @Query(sort: \SessionLog.startedAt, order: .reverse) private var sessions: [SessionLog]
    @State private var playerRoutine: RoutinePayload?
    @State private var showingImport = false

    private var activeRoutine: Routine? {
        routines.first(where: \.isActive) ?? routines.first
    }

    private var doneToday: Bool {
        guard let latest = sessions.first?.startedAt else { return false }
        return Calendar.current.isDateInToday(latest)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let routine = activeRoutine {
                        weekCard(for: routine)
                        routineCard(routine)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
        }
        .fullScreenCover(item: $playerRoutine) { payload in
            PlayerView(routine: payload)
        }
        .sheet(isPresented: $showingImport) {
            ImportView()
        }
    }

    private func weekCard(for routine: Routine) -> some View {
        let dates = sessions.map(\.startedAt)
        let done = ComplianceEngine.currentWeekCount(sessionDates: dates)
        let target = max(1, routine.daysPerWeek)
        let streak = ComplianceEngine.dayStreak(sessionDates: dates)

        return HStack(spacing: 20) {
            ZStack {
                TimerRing(progress: Double(done) / Double(target), lineWidth: 8)
                    .frame(width: 64, height: 64)
                Text("\(done)/\(target)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("This week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(done >= target ? "Target met" : "\(target - done) more to go")
                    .font(.headline)
                if streak > 1 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func routineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.title3.weight(.semibold))
                Text("\(routine.exercises.count) exercises · about \(Format.duration(routine.payload.estimatedSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if doneToday {
                Label("Done today", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                playerRoutine = routine.payload
            } label: {
                Label(doneToday ? "Start again" : "Start session", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(routine.exercises.isEmpty)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(routine.orderedExercises.prefix(6)) { exercise in
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                        Spacer()
                        Text(exercise.goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if routine.exercises.count > 6 {
                    Text("+ \(routine.exercises.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No routine yet", systemImage: "doc.text.viewfinder")
        } description: {
            Text("Import screenshots of your PT's exercise sheet and Mend will turn them into a guided routine — entirely on this device.")
        } actions: {
            Button("Import screenshots") {
                showingImport = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 80)
    }
}
