import SwiftUI
import DataKit

/// Editing the active routine after setup.
public struct EditRoutineView: View {
    @State private var viewModel: EditRoutineViewModel
    private let onDone: () -> Void

    public init(routine: Routine, repo: RoutineRepository, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: EditRoutineViewModel(routine: routine, repo: repo))
        self.onDone = onDone
    }

    public var body: some View {
        RoutineEditorView(
            viewModel: viewModel.editor,
            title: "Edit routine",
            onSave: { if viewModel.save() { onDone() } },
            onCancel: onDone
        )
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
