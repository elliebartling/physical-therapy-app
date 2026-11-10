import SwiftUI
import ParsingKit
import DataKit

public struct ExerciseEditorView: View {
    @Binding public var exercise: ParsedRoutine.ParsedExercise

    enum Kind: String, CaseIterable, Identifiable {
        case reps = "Reps × Sets", time = "Time × Sets"
        public var id: Self { self }
    }

    @State private var kind: Kind

    public init(exercise: Binding<ParsedRoutine.ParsedExercise>) {
        self._exercise = exercise
        self._kind = State(initialValue: exercise.wrappedValue.durationSec == nil ? .reps : .time)
    }

    public var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                    .font(AppFont.mono(16))
            }
            Section("Target") {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, new in
                    switch new {
                    case .reps:
                        exercise.durationSec = nil
                        if exercise.reps == nil { exercise.reps = 10 }
                    case .time:
                        exercise.reps = nil
                        if exercise.durationSec == nil { exercise.durationSec = 30 }
                    }
                }

                switch kind {
                case .reps:
                    Stepper("Reps: \(exercise.reps ?? 0)", value: Binding(
                        get: { exercise.reps ?? 0 },
                        set: { exercise.reps = $0 }), in: 1...100)
                case .time:
                    Stepper("Seconds: \(exercise.durationSec ?? 0)", value: Binding(
                        get: { exercise.durationSec ?? 0 },
                        set: { exercise.durationSec = $0 }), in: 5...600, step: 5)
                }
                Stepper("Sets: \(exercise.sets)", value: $exercise.sets, in: 1...10)
            }
            Section("Rest") {
                Stepper("Rest: \(exercise.restSec)s", value: $exercise.restSec, in: 0...120, step: 5)
            }
            Section("Side") {
                Picker("Side", selection: $exercise.side) {
                    ForEach(Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                }
            }
            Section("Notes") {
                TextField("Notes", text: $exercise.notes, axis: .vertical).lineLimit(3...8)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
