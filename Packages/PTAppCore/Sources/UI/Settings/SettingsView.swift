import SwiftUI

public struct SettingsView: View {
    @Bindable public var viewModel: SettingsViewModel
    public var onReplaceRoutine: () -> Void

    public init(viewModel: SettingsViewModel, onReplaceRoutine: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onReplaceRoutine = onReplaceRoutine
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    Toggle("Daily reminder", isOn: $viewModel.reminderEnabled)
                    if viewModel.reminderEnabled {
                        DatePicker("Time", selection: $viewModel.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                .onChange(of: viewModel.reminderEnabled) { _, _ in Task { await viewModel.applyReminder() } }
                .onChange(of: viewModel.reminderTime) { _, _ in Task { await viewModel.applyReminder() } }

                Section("Sync") {
                    Label("Local only (v1)", systemImage: "iphone")
                }

                Section("Routine") {
                    Button("Replace routine", role: .destructive, action: onReplaceRoutine)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
