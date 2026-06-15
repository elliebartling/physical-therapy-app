import SwiftUI
import ParsingKit

public struct RoutineEditorView: View {
    @Bindable public var viewModel: RoutineEditorViewModel
    public var onSave: () -> Void

    public init(viewModel: RoutineEditorViewModel, onSave: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine name", text: $viewModel.name)
                        .font(AppFont.mono(18, weight: .medium))
                }
                Section("Exercises") {
                    ForEach($viewModel.exercises, id: \.id) { $ex in
                        NavigationLink(destination: ExerciseEditorView(exercise: $ex)) {
                            HStack {
                                Text(ex.name).font(AppFont.mono(16))
                                Spacer()
                                Text(summary(for: ex)).font(AppFont.body(13)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: viewModel.remove)
                    .onMove(perform: viewModel.move)

                    Button {
                        viewModel.addExercise()
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                }
            }
            .toolbar {
                EditButton()
                Button("Save", action: onSave).bold()
            }
        }
    }

    private func summary(for ex: ParsedRoutine.ParsedExercise) -> String {
        if let dur = ex.durationSec { return "\(dur)s × \(ex.sets)" }
        return "\(ex.reps ?? 0) × \(ex.sets)"
    }
}
