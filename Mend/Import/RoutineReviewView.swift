import SwiftUI
import SwiftData

/// Editable review of an extracted (or blank) routine before it's saved.
/// Doubles as the manual-entry flow.
struct RoutineReviewView: View {
    @Environment(\.modelContext) private var context
    @State private var draft: RoutinePayload
    let onDone: () -> Void

    init(draft: RoutinePayload, onDone: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $draft.name)
                Stepper("\(draft.daysPerWeek)× per week", value: $draft.daysPerWeek, in: 1...7)
                if let notes = draft.clinicianNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach($draft.exercises) { $exercise in
                    NavigationLink {
                        ExerciseFormView(exercise: $exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name.isEmpty ? "Untitled exercise" : exercise.name)
                            Text(exercise.goalDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { draft.exercises.remove(atOffsets: $0) }
                .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    draft.exercises.append(ExercisePayload(name: ""))
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Check everything against your PT's sheet — extraction is good, not perfect.")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.exercises.isEmpty)
            }
        }
    }

    private func save() {
        let routine = Routine(
            id: draft.id,
            name: draft.name,
            clinicianNotes: draft.clinicianNotes,
            daysPerWeek: draft.daysPerWeek
        )
        context.insert(routine)
        for (index, payload) in draft.exercises.enumerated() {
            let exercise = Exercise(
                id: payload.id,
                name: payload.name,
                details: payload.details,
                orderIndex: index,
                sets: payload.sets,
                reps: payload.reps,
                holdSeconds: payload.holdSeconds,
                restSeconds: payload.restSeconds,
                isPerSide: payload.isPerSide,
                equipment: payload.equipment
            )
            exercise.routine = routine
            context.insert(exercise)
        }

        // The newest routine becomes the active one.
        let others = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        for other in others where other.id != routine.id {
            other.isActive = false
        }
        routine.isActive = true

        try? context.save()
        PhoneConnectivity.shared.pushAllRoutines()
        onDone()
    }
}

struct ExerciseFormView: View {
    @Binding var exercise: ExercisePayload

    private enum Mode: String, CaseIterable {
        case reps = "Reps"
        case hold = "Hold"
    }

    private var mode: Binding<Mode> {
        Binding {
            exercise.isTimed ? .hold : .reps
        } set: { newValue in
            switch newValue {
            case .hold:
                exercise.holdSeconds = exercise.holdSeconds ?? 30
                exercise.reps = nil
            case .reps:
                exercise.reps = exercise.reps ?? 10
                exercise.holdSeconds = nil
            }
        }
    }

    private var detailsBinding: Binding<String> {
        Binding {
            exercise.details ?? ""
        } set: {
            exercise.details = $0.isEmpty ? nil : $0
        }
    }

    private var equipmentBinding: Binding<String> {
        Binding {
            exercise.equipment ?? ""
        } set: {
            exercise.equipment = $0.isEmpty ? nil : $0
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                Picker("Type", selection: mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Prescription") {
                Stepper("\(exercise.sets) sets", value: $exercise.sets, in: 1...10)
                if exercise.isTimed {
                    Stepper(
                        "Hold \(Format.duration(exercise.holdSeconds ?? 30))",
                        value: Binding(
                            get: { exercise.holdSeconds ?? 30 },
                            set: { exercise.holdSeconds = $0 }
                        ),
                        in: 5...600,
                        step: 5
                    )
                } else {
                    Stepper(
                        "\(exercise.reps ?? 10) reps",
                        value: Binding(
                            get: { exercise.reps ?? 10 },
                            set: { exercise.reps = $0 }
                        ),
                        in: 1...100
                    )
                }
                Stepper(
                    "Rest \(Format.duration(exercise.restSeconds))",
                    value: $exercise.restSeconds,
                    in: 0...300,
                    step: 5
                )
                Toggle("Each side separately", isOn: $exercise.isPerSide)
            }

            Section("Details") {
                TextField("Equipment (e.g. resistance band)", text: equipmentBinding)
                TextField("Instructions", text: detailsBinding, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle(exercise.name.isEmpty ? "Exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
