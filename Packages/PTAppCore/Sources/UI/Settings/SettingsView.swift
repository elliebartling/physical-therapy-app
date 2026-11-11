import SwiftUI

public struct SettingsView: View {
    @Bindable public var viewModel: SettingsViewModel
    public var onReplaceRoutine: () -> Void
    public var onDone: () -> Void

    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.signal.rawValue

    public init(viewModel: SettingsViewModel,
                onReplaceRoutine: @escaping () -> Void,
                onDone: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onReplaceRoutine = onReplaceRoutine
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    AccentPicker(selection: $accentRaw)
                }

                Section("Reminder") {
                    Toggle("Daily reminder", isOn: $viewModel.reminderEnabled)
                    if viewModel.reminderEnabled {
                        DatePicker("Time", selection: $viewModel.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                .onChange(of: viewModel.reminderEnabled) { _, _ in Task { await viewModel.applyReminder() } }
                .onChange(of: viewModel.reminderTime) { _, _ in Task { await viewModel.applyReminder() } }

                HealthSettingsSection(viewModel: viewModel)

                Section("Sync") {
                    Label("Local only (v1)", systemImage: "iphone")
                }

                Section("Routine") {
                    Button("Replace routine", role: .destructive, action: onReplaceRoutine)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.surface)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

/// Six accent swatches. The accent fills the timer, today's square and the start button.
struct AccentPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(AccentChoice.allCases) { choice in
                    swatch(for: choice)
                }
            }
            Text("Fills the timer, today's square and the start button. Text on it stays black, so every option stays readable.")
                .font(AppFont.body(13))
                .foregroundStyle(AppColor.inkSecondary)
        }
        .padding(.vertical, 6)
    }

    private func swatch(for choice: AccentChoice) -> some View {
        let isSelected = choice.rawValue == selection
        return Button {
            selection = choice.rawValue
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(choice.color)
                    .frame(height: 52)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppColor.onAccent)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(AppColor.ink, lineWidth: isSelected ? 2 : 0)
                            .padding(-3)
                    }
                Text(choice.name.uppercased())
                    .font(AppFont.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.inkSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Optional saving to Apple Health, and what sessions are saved as.
private struct HealthSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle("Save sessions to Health", isOn: Binding(
                get: { viewModel.healthEnabled },
                set: { enabled in Task { await viewModel.setHealthEnabled(enabled) } }
            ))
            if viewModel.healthEnabled {
                Picker("Save as", selection: $viewModel.healthKind) {
                    ForEach(HealthWorkoutKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if let message = viewModel.healthMessage { return message }
        if viewModel.healthEnabled {
            return "Each session you do or log is saved as a workout. Sessions you log later are marked as entered by you."
        }
        return "Off. Mend only saves workouts; it never reads your Health data."
    }
}
