import SwiftUI

/// "Talk it through": dictate or type the routine, then turn it into exercises.
public struct BrainDumpView: View {
    @State private var viewModel: BrainDumpViewModel
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void

    @Environment(\.appAccent) private var accent

    public init(dictation: Dictating = SpeechDictation(),
                onSubmit: @escaping (String) -> Void,
                onCancel: @escaping () -> Void) {
        _viewModel = State(initialValue: BrainDumpViewModel(dictation: dictation))
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text("Talk it through")
                .font(AppFont.display(36, weight: .bold))
                .tracking(-1.4)
                .padding(.top, 20)
            Text("Describe your exercises like you'd tell a friend: “clamshells, three sets of twelve each side, then a thirty-second side plank.” You can edit the text afterwards.")
                .font(AppFont.body(15))
                .foregroundStyle(AppColor.inkSecondary)
                .padding(.top, 10)
            transcriptEditor.padding(.top, 18)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(AppFont.body(14))
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.top, 10)
            }
            controls.padding(.top, AppSpacing.s(2))
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.bottom, AppSpacing.s(1))
        .background(AppColor.surface.ignoresSafeArea())
        .foregroundStyle(AppColor.ink)
        .onDisappear { viewModel.stopListening() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Cancel") {
                    viewModel.stopListening()
                    onCancel()
                }
                .font(AppFont.display(16, weight: .semibold))
                .frame(minHeight: 44)
                Spacer()
                SectionLabel(viewModel.isListening ? "Listening…" : "Brain dump")
            }
            InkRule(weight: 2)
        }
        .padding(.top, AppSpacing.s(1))
    }

    private var transcriptEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.transcript)
                .font(AppFont.body(17))
                .scrollContentBackground(.hidden)
                .padding(10)
                .accessibilityLabel("Your routine, in your words")
            if viewModel.transcript.isEmpty {
                Text("Your words appear here as you talk. You can type, too.")
                    .font(AppFont.body(17))
                    .foregroundStyle(AppColor.inkSecondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(viewModel.isListening ? accent : AppColor.hairline,
                              lineWidth: viewModel.isListening ? 2 : 1)
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                micButton
                Button(action: submit) {
                    HStack {
                        Text("Make my routine")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(AppFont.display(17, weight: .semibold))
                    .padding(.horizontal, 22)
                }
                .buttonStyle(InkGlassButtonStyle())
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.5)
            }
        }
    }

    private var micButton: some View {
        Button {
            Task { await viewModel.toggleListening() }
        } label: {
            Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(viewModel.isListening ? AppColor.onAccent : AppColor.ink)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
                .glassEffect(viewModel.isListening ? .regular.tint(accent).interactive() : .regular.interactive(),
                             in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isListening ? "Stop listening" : "Start listening")
    }

    private func submit() {
        viewModel.stopListening()
        onSubmit(viewModel.transcript)
    }
}
