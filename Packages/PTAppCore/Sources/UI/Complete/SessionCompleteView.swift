import SwiftUI

public struct SessionCompleteView: View {
    public let newStreak: Int
    public let onDone: () -> Void

    @State private var pulse = false

    public init(newStreak: Int, onDone: @escaping () -> Void) {
        self.newStreak = newStreak
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            AppColor.surface.ignoresSafeArea()
            VStack(spacing: AppSpacing.s(3)) {
                Text("Nice work").font(AppFont.mono(28, weight: .medium))
                Text("\(newStreak)")
                    .font(AppFont.mono(140, weight: .bold))
                    .foregroundStyle(AppColor.accent)
                    .scaleEffect(pulse ? 1.0 : 0.6)
                    .animation(.snappy(duration: 0.4), value: pulse)
                Text("DAY STREAK").font(AppFont.mono(12, weight: .medium)).tracking(2)
                Button("Done", action: onDone)
                    .font(AppFont.mono(18, weight: .medium))
                    .padding(.top, AppSpacing.s(4))
            }
            .padding(AppSpacing.screenPadding)
        }
        .onAppear { pulse = true }
    }
}
