import SwiftUI
import SwiftData

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @Query private var routines: [Routine]
    @State private var playerRoutine: RoutinePayload?

    var body: some View {
        List {
            Section {
                Toggle("Active routine", isOn: activeBinding)
                Stepper("\(routine.daysPerWeek)× per week", value: $routine.daysPerWeek, in: 1...7)
                if let notes = routine.clinicianNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                ForEach(routine.orderedExercises) { exercise in
                    NavigationLink {
                        ExerciseFormView(exercise: binding(for: exercise))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            Text(exercise.goalDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteExercises)

                Button {
                    addExercise()
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            }

            Section {
                Button {
                    playerRoutine = routine.payload
                } label: {
                    Label("Start session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(routine.exercises.isEmpty)
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playerRoutine) { payload in
            PlayerView(routine: payload)
        }
        .onDisappear {
            try? context.save()
            PhoneConnectivity.shared.pushAllRoutines()
        }
    }

    private var activeBinding: Binding<Bool> {
        Binding {
            routine.isActive
        } set: { newValue in
            if newValue {
                for other in routines where other.id != routine.id {
                    other.isActive = false
                }
            }
            routine.isActive = newValue
        }
    }

    /// Edits a persisted exercise through the same payload-based form used at import.
    private func binding(for exercise: Exercise) -> Binding<ExercisePayload> {
        Binding {
            exercise.payload
        } set: { payload in
            exercise.name = payload.name
            exercise.details = payload.details
            exercise.sets = payload.sets
            exercise.reps = payload.reps
            exercise.holdSeconds = payload.holdSeconds
            exercise.restSeconds = payload.restSeconds
            exercise.isPerSide = payload.isPerSide
            exercise.equipment = payload.equipment
        }
    }

    private func addExercise() {
        let nextIndex = (routine.exercises.map(\.orderIndex).max() ?? -1) + 1
        let exercise = Exercise(name: "New exercise", orderIndex: nextIndex)
        exercise.routine = routine
        context.insert(exercise)
    }

    private func deleteExercises(at offsets: IndexSet) {
        let ordered = routine.orderedExercises
        for index in offsets {
            context.delete(ordered[index])
        }
    }
}
