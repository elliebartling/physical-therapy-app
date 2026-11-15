import SwiftUI

/// A sheet for logging a session done away from the app.
public struct LogSessionView: View {
    @State private var viewModel: LogSessionViewModel
    private let onDone: () -> Void

    public init(viewModel: LogSessionViewModel, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $viewModel.date,
                               in: ...viewModel.latestDate, displayedComponents: .date)
                }
                if !viewModel.workouts.isEmpty {
                    otherWorkoutsSection
                }
                Section {
                    ForEach(viewModel.items) { item in
                        Toggle(isOn: Binding(get: { item.isDone },
                                             set: { viewModel.setDone($0, for: item.id) })) {
                            LogExerciseLabel(name: item.name, prescription: item.prescription,
                                             coveredBy: item.coveredBy)
                        }
                    }
                } header: {
                    Text("What you did")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Log a session")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: Calendar.current.startOfDay(for: viewModel.date)) { await viewModel.loadWorkouts() }
            // Back from saying what a workout covers.
            .onAppear { viewModel.refreshRules() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if viewModel.save() { onDone() } }
                        .bold()
                        .disabled(!viewModel.canSave)
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.dismissError() } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// The day's workouts from Apple Health, each counted for what it covers.
    private var otherWorkoutsSection: some View {
        Section {
            ForEach(viewModel.workouts) { option in
                if option.covers.isEmpty {
                    if let source = viewModel.otherWorkouts {
                        NavigationLink {
                            CoverageRuleEditor(model: CoverageRuleEditorModel(
                                activity: option.workout.activity,
                                exercises: viewModel.coverableExercises,
                                source: source
                            ))
                        } label: {
                            WorkoutOptionLabel(option: option, detail: "Choose what it covers")
                        }
                    }
                } else {
                    Toggle(isOn: Binding(get: { option.isCounted },
                                         set: { viewModel.setCounted($0, for: option.id) })) {
                        WorkoutOptionLabel(
                            option: option,
                            detail: "Covers " + viewModel.coveredNames(for: option).formatted(.list(type: .and))
                        )
                    }
                }
            }
        } header: {
            Text("From Apple Health")
        } footer: {
            Text("Counted exercises are marked as covered by that workout, so your PT can tell.")
        }
    }

    private var footer: String {
        if !viewModel.canSave { return "Check at least one exercise to log a session." }
        if viewModel.isEveryExerciseDone { return "Counts toward your week, just like a guided session." }
        return "Saved as a partial session. Check every exercise to count it toward your week."
    }
}

private struct LogExerciseLabel: View {
    let name: String
    let prescription: String
    var coveredBy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(AppFont.display(16, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(prescription)
                    .font(AppFont.mono(12))
                    .foregroundStyle(AppColor.inkSecondary)
                if let coveredBy {
                    Text(coveredBy.uppercased())
                        .font(AppFont.mono(10, weight: .medium))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay { Rectangle().strokeBorder(AppColor.hairline, lineWidth: 1) }
                        .accessibilityLabel("covered by \(coveredBy.lowercased())")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One of the day's workouts: what, how long, when, and what it covers.
private struct WorkoutOptionLabel: View {
    let option: LogSessionViewModel.WorkoutOption
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(option.name), \(option.workout.minutes) min")
                .font(AppFont.display(16, weight: .medium))
            Text(option.workout.start.formatted(date: .omitted, time: .shortened) + " — " + detail)
                .font(AppFont.body(13))
                .foregroundStyle(AppColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
