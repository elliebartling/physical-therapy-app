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
    /// Whether a frame has really arrived. Frame 1 is the gate: it is the only
    /// one shown until this is true. If 2 or 3 are slow, scrubbing to them shows
    /// a blank square, which beats waiting on all three before showing anything.
    @State private var hasLoadedPicture: Bool

    init(art: ArtChoice, hasLoadedPicture: Bool = false) {
        self.art = art
        _hasLoadedPicture = State(initialValue: hasLoadedPicture)
    }

    static func clamped(_ frame: Int) -> Int {
        min(max(frame, frames.lowerBound), frames.upperBound)
    }

    private var canHavePicture: Bool {
        guard case .library(let slug) = art else { return false }
        return ExerciseCatalog.bundled.entry(slug: slug) != nil
    }

    var body: some View {
        if canHavePicture {
            VStack(alignment: .leading, spacing: 12) {
                // Always laid out, so nothing jumps when the picture arrives.
                ExerciseFigure(art: art, frame: frame) { loaded in
                    if loaded { hasLoadedPicture = true }
                }
                .frame(maxWidth: 320, maxHeight: 320)
                .frame(maxWidth: .infinity)
                if hasLoadedPicture {
                    scrub
                    credit
                }
            }
        }
    }

    private var credit: some View {
        Text(Self.credit)
            .font(.caption2.monospaced())
            .foregroundStyle(AppColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
