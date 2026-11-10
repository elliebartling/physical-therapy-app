import SwiftUI

public struct SessionCompleteView: View {
    public let newStreak: Int
    public let onDone: () -> Void

    @State private var appeared = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(newStreak: Int, onDone: @escaping () -> Void) {
        self.newStreak = newStreak
        self.onDone = onDone
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surface.ignoresSafeArea()
            completionField
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        SectionLabel("Session complete")
                        Spacer()
                    }
                    InkRule(weight: 2)
                }
                .padding(.top, AppSpacing.s(1))
                Text("Nice work.")
                    .font(AppFont.display(56, weight: .bold))
                    .tracking(-2.4)
                    .padding(.top, 26)
                Spacer()
                streak
                doneButton.padding(.top, AppSpacing.s(3))
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.s(1))
        }
        .foregroundStyle(AppColor.ink)
        .onAppear { appeared = true }
    }

    /// The timer field filling back up: the visual "done".
    private var completionField: some View {
        Rectangle()
            .fill(accent.fieldTone(for: colorScheme))
            .containerRelativeFrame(.vertical) { length, _ in length * (appeared ? 0.5 : 0) }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: appeared)
            .accessibilityHidden(true)
    }

    private var streak: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("\(newStreak)")
                .font(AppFont.display(176, weight: .bold))
                .tracking(-10)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6, anchor: .bottomLeading)
                .animation(.snappy(duration: 0.4), value: appeared)
            Text("DAY\nSTREAK")
                .font(AppFont.mono(12, weight: .medium))
                .tracking(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(newStreak)-day streak")
    }

    private var doneButton: some View {
        Button(action: onDone) {
            HStack {
                Text("Done")
                Spacer()
                Image(systemName: "checkmark")
            }
            .font(AppFont.display(17, weight: .semibold))
            .padding(.horizontal, 22)
        }
        .buttonStyle(InkGlassButtonStyle())
    }
}
