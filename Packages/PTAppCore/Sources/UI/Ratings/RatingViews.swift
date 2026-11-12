import SwiftUI
import DataKit

/// The four ratings as large glass capsules; tapping the selected one clears it.
struct RatingChips: View {
    let selection: ExerciseRating?
    let onSelect: (ExerciseRating?) -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(ExerciseRating.allCases, id: \.self) { rating in
                    chip(rating)
                }
            }
        }
    }

    private func chip(_ rating: ExerciseRating) -> some View {
        let isSelected = rating == selection
        return Button {
            onSelect(isSelected ? nil : rating)
        } label: {
            Text(rating.title)
                .font(AppFont.display(14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 4)
                .contentShape(Capsule())
                .glassEffect(isSelected ? .regular.tint(accent).interactive() : .regular.interactive(),
                             in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rating.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shown on the session screen after an exercise when rating after each one.
/// It never blocks the timer and goes away on its own.
struct RatingPromptCard: View {
    let exerciseName: String
    let onRate: (ExerciseRating) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("How was \(exerciseName)?")
                    .font(AppFont.display(17, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rating")
            }
            RatingChips(selection: nil) { rating in
                if let rating { onRate(rating) }
            }
        }
        .padding(.leading, 16)
        .padding([.trailing, .bottom], 12)
        .padding(.top, 4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rate \(exerciseName)")
    }
}
