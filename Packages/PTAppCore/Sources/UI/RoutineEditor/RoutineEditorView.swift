import SwiftUI
import ParsingKit
import DataKit

public struct RoutineEditorView: View {
    @Bindable public var viewModel: RoutineEditorViewModel
    public var title: String?
    public var onSave: () -> Void
    public var onCancel: (() -> Void)?

    public init(viewModel: RoutineEditorViewModel,
                title: String? = nil,
                onSave: @escaping () -> Void,
                onCancel: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine name", text: $viewModel.name, axis: .vertical)
                        .font(AppFont.display(20, weight: .semibold))
                        .lineLimit(1...3)
                }
                Section("Exercises") {
                    ForEach($viewModel.exercises, id: \.id) { $ex in
                        NavigationLink(destination: ExerciseEditorView(exercise: $ex, imported: viewModel.importedSuggestions[ex.id])) {
                            ExerciseSummaryRow(name: ex.name, summary: summary(for: ex), art: ex.art)
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
            .navigationTitle(title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave).bold()
                }
            }
        }
    }

    private func summary(for ex: ParsedRoutine.ParsedExercise) -> String {
        let base = ex.durationSec.map { "\(ex.sets)×\($0)s" } ?? "\(ex.sets)×\(ex.reps ?? 0)"
        switch ex.side.lowercased() {
        case "alternating": return base + " L/R"
        case "left": return base + " L"
        case "right": return base + " R"
        default: return base
        }
    }
}

/// The full exercise name, wrapping as needed, with its prescription underneath.
private struct ExerciseSummaryRow: View {
    let name: String
    let summary: String
    let art: ArtChoice

    var body: some View {
        HStack(spacing: 12) {
            ExerciseFigure(art: art)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(AppFont.display(16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary)
                    .font(AppFont.mono(12))
                    .foregroundStyle(AppColor.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}
