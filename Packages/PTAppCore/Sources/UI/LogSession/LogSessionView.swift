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
                Section {
                    ForEach($viewModel.items) { $item in
                        Toggle(isOn: $item.isDone) {
                            LogExerciseLabel(name: item.name, prescription: item.prescription)
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

    private var footer: String {
        if !viewModel.canSave { return "Check at least one exercise to log a session." }
        if viewModel.isEveryExerciseDone { return "Counts toward your week, just like a guided session." }
        return "Saved as a partial session. Check every exercise to count it toward your week."
    }
}

private struct LogExerciseLabel: View {
    let name: String
    let prescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(AppFont.display(16, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text(prescription)
                .font(AppFont.mono(12))
                .foregroundStyle(AppColor.inkSecondary)
        }
        .padding(.vertical, 2)
    }
}
