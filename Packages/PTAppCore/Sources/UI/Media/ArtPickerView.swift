import SwiftUI
import DataKit
import MediaKit

/// Chooses the picture for one exercise.
///
/// Reached from `ExerciseEditorView`, which both the post-import review and
/// the saved-routine editor use, so this one screen is how a picture is
/// corrected at either moment. Suggestions come from re-running the matcher
/// on demand; "No picture" is always on offer, even before they arrive.
public struct ArtPickerView: View {
    @Binding private var art: ArtChoice
    private let exerciseName: String
    private let matcher: ExerciseMatcher

    @State private var suggestions: [CatalogEntry]
    @Environment(\.dismiss) private var dismiss

    public init(art: Binding<ArtChoice>, exerciseName: String, matcher: ExerciseMatcher = .init()) {
        self.init(art: art, exerciseName: exerciseName, matcher: matcher, initialSuggestions: [])
    }

    init(art: Binding<ArtChoice>, exerciseName: String, matcher: ExerciseMatcher = .init(),
         initialSuggestions: [CatalogEntry]) {
        self._art = art
        self.exerciseName = exerciseName
        self.matcher = matcher
        self._suggestions = State(initialValue: initialSuggestions)
    }

    /// The matcher's choice first, then its alternatives. Slugs the bundled
    /// catalogue no longer knows are dropped rather than shown blank.
    static func suggestions(from result: MatchResult,
                            catalog: ExerciseCatalog = .bundled) -> [CatalogEntry] {
        var slugs: [String] = []
        if case .library(let slug) = result.choice { slugs.append(slug) }
        slugs.append(contentsOf: result.alternatives)
        var seen = Set<String>()
        return slugs.compactMap { slug in
            guard seen.insert(slug).inserted else { return nil }
            return catalog.entry(slug: slug)
        }
    }

    static func loadSuggestions(name: String, matcher: ExerciseMatcher) async -> [CatalogEntry] {
        suggestions(from: await matcher.match(name: name, notes: ""))
    }

    public var body: some View {
        List {
            Section {
                ForEach(suggestions) { entry in
                    ArtOptionRow(
                        title: entry.name,
                        art: .library(slug: entry.slug),
                        isSelected: art == .library(slug: entry.slug)
                    ) { choose(.library(slug: entry.slug)) }
                }
            } header: {
                if !suggestions.isEmpty { Text("Suggestions") }
            }
            Section {
                ArtOptionRow(title: "No picture", art: ArtChoice.none,
                             isSelected: art == ArtChoice.none) { choose(ArtChoice.none) }
            }
        }
        .navigationTitle("Picture")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: exerciseName) {
            let loaded = await Self.loadSuggestions(name: exerciseName, matcher: matcher)
            guard !Task.isCancelled else { return }
            suggestions = loaded
        }
    }

    private func choose(_ choice: ArtChoice) {
        art = choice
        dismiss()
    }
}

/// One tappable choice: a small figure and the exercise's name.
private struct ArtOptionRow: View {
    let title: String
    let art: ArtChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ExerciseFigure(art: art)
                    .frame(width: 56, height: 56)
                Text(title)
                    .font(AppFont.display(16, weight: .medium))
                    .foregroundStyle(AppColor.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColor.ink)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
