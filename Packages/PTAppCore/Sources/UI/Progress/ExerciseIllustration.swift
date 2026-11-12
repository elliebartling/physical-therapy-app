import SwiftUI
import DataKit
import MediaKit

/// The large figure on the exercise screen, with a way to step through its
/// three frames (start, middle, end). Nothing moves on its own.
///
/// Renders nothing when there is no picture to show, so no empty square and
/// no credit for an illustration that is not there.
struct ExerciseIllustration: View {
    static let credit = "Exercise illustrations by Bryl Lim, licensed CC BY-SA 4.0. Derived from Everkinetic."
    static let frames = 1...3

    let art: ArtChoice
    @State private var frame = 1

    static func clamped(_ frame: Int) -> Int {
        min(max(frame, frames.lowerBound), frames.upperBound)
    }

    private var hasPicture: Bool {
        guard case .library(let slug) = art else { return false }
        return ExerciseCatalog.bundled.entry(slug: slug) != nil
    }

    var body: some View {
        if hasPicture {
            VStack(alignment: .leading, spacing: 12) {
                ExerciseFigure(art: art, frame: frame)
                    .frame(maxWidth: 320, maxHeight: 320)
                    .frame(maxWidth: .infinity)
                scrub
                Text(Self.credit)
                    .font(AppFont.mono(10))
                    .foregroundStyle(AppColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A segmented control: operable by touch, VoiceOver and keyboard alike.
    private var scrub: some View {
        Picker("Picture of the movement",
               selection: Binding(get: { frame }, set: { frame = Self.clamped($0) })) {
            Text("Start").tag(1)
            Text("Middle").tag(2)
            Text("End").tag(3)
        }
        .pickerStyle(.segmented)
    }
}
