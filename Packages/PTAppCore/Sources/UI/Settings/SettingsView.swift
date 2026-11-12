import SwiftUI

public struct SettingsView: View {
    @Bindable public var viewModel: SettingsViewModel
    public var onReplaceRoutine: () -> Void
    public var onDone: () -> Void

    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.signal.rawValue
    @AppStorage(RatingTiming.storageKey) private var ratingTiming = RatingTiming.atEnd
    @AppStorage(AppIconStyle.storageKey) private var iconStyle = AppIconStyle.rangeOfMotion
    @AppStorage(AppIconStyle.matchesAccentKey) private var iconMatchesAccent = true

    private var accent: AccentChoice { AccentChoice(rawValue: accentRaw) ?? .signal }

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
                Section {
                    AccentPicker(selection: $accentRaw)
                    AppIconPicker(selection: $iconStyle,
                                  accent: iconMatchesAccent ? accent.color : AccentChoice.signal.color)
                    Toggle("Icon matches accent", isOn: $iconMatchesAccent)
                } header: {
                    Text("Appearance")
                } footer: {
                    if let message = viewModel.appIconMessage {
                        Text(message)
                    }
                }
                .onChange(of: accentRaw) { _, _ in syncAppIcon() }
                .onChange(of: iconStyle) { _, _ in syncAppIcon() }
                .onChange(of: iconMatchesAccent) { _, _ in syncAppIcon() }

                Section("Reminder") {
                    Toggle("Daily reminder", isOn: $viewModel.reminderEnabled)
                    if viewModel.reminderEnabled {
                        DatePicker("Time", selection: $viewModel.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                .onChange(of: viewModel.reminderEnabled) { _, _ in Task { await viewModel.applyReminder() } }
                .onChange(of: viewModel.reminderTime) { _, _ in Task { await viewModel.applyReminder() } }

                Section {
                    Picker("Rate exercises", selection: $ratingTiming) {
                        ForEach(RatingTiming.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Ratings")
                } footer: {
                    Text("Easy, about right, hard or painful — always optional. At the end, you can also note pain and anything for your PT.")
                }

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

extension SettingsView {
    private func syncAppIcon() {
        Task { await viewModel.applyAppIcon(style: iconStyle, accent: accent, matchesAccent: iconMatchesAccent) }
    }
}

/// The two home-screen icon designs, drawn in the current accent.
struct AppIconPicker: View {
    @Binding var selection: AppIconStyle
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App icon")
            HStack(spacing: 20) {
                ForEach(AppIconStyle.allCases) { style in
                    option(style)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6)
    }

    private func option(_ style: AppIconStyle) -> some View {
        let isSelected = style == selection
        return Button {
            selection = style
        } label: {
            VStack(spacing: 6) {
                AppIconPreview(style: style, accent: accent)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14.3, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(AppColor.ink, lineWidth: isSelected ? 2 : 0)
                            .padding(-3)
                    }
                Text(style.title.uppercased())
                    .font(AppFont.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(AppColor.inkSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
