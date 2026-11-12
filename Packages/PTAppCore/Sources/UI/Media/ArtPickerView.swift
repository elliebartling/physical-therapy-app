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
    let notes: String

    @State private var suggestions: [CatalogEntry]
    @State private var hasLoaded = false
    @Environment(\.dismiss) private var dismiss

    public init(art: Binding<ArtChoice>, exerciseName: String, notes: String = "",
                matcher: ExerciseMatcher = .init()) {
        self.init(art: art, exerciseName: exerciseName, notes: notes, matcher: matcher,
                  initialSuggestions: [])
    }

    init(art: Binding<ArtChoice>, exerciseName: String, notes: String = "",
         matcher: ExerciseMatcher = .init(), initialSuggestions: [CatalogEntry]) {
        self._art = art
        self.exerciseName = exerciseName
        self.notes = notes
        self.matcher = matcher
        self._suggestions = State(initialValue: initialSuggestions)
    }

    private struct LoadKey: Equatable {
        let name: String
        let notes: String
    }

    /// The current choice first (so it is checked even when the matcher no
    /// longer suggests it), then the suggestions.
    static func displayedEntries(current: ArtChoice, suggestions: [CatalogEntry],
                                 catalog: ExerciseCatalog = .bundled) -> [CatalogEntry] {
        guard case .library(let slug) = current,
              !suggestions.contains(where: { $0.slug == slug }),
              let entry = catalog.entry(slug: slug) else { return suggestions }
        return [entry] + suggestions
    }

    /// What VoiceOver should say the picture currently is.
    static func pictureDescription(for art: ArtChoice, catalog: ExerciseCatalog = .bundled) -> String {
        switch art {
        case .library(let slug): return catalog.entry(slug: slug)?.name ?? "Not set"
        case .none: return "None"
        case .unmatched: return "Not set"
        }
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

    static func loadSuggestions(name: String, notes: String = "",
                                matcher: ExerciseMatcher) async -> [CatalogEntry] {
        suggestions(from: await matcher.match(name: name, notes: notes))
    }

    private var entries: [CatalogEntry] {
        Self.displayedEntries(current: art, suggestions: suggestions)
    }

    public var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        ArtOptionRow(
                            title: entry.name,
                            art: .library(slug: entry.slug),
                            isSelected: art == .library(slug: entry.slug)
                        ) { choose(.library(slug: entry.slug)) }
                    }
                } header: {
                    Text("Suggestions")
                }
            }
            Section {
                ArtOptionRow(title: "No picture", art: ArtChoice.none,
                             isSelected: art == ArtChoice.none) { choose(ArtChoice.none) }
            } footer: {
                if suggestions.isEmpty {
                    Text(hasLoaded ? "No suggestions for this exercise." : "Finding suggestions…")
                }
            }
        }
        .navigationTitle("Picture")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: LoadKey(name: exerciseName, notes: notes)) {
            let loaded = await Self.loadSuggestions(name: exerciseName, notes: notes, matcher: matcher)
            guard !Task.isCancelled else { return }
            suggestions = loaded
            hasLoaded = true
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
