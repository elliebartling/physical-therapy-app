import SwiftUI
import UIKit
import DataKit
import MediaKit

public extension EnvironmentValues {
    /// The store exercise figures read their frames from. Tests and previews
    /// pass a store to `ExerciseFigure` directly instead.
    @Entry var artStore: ArtStore = ArtStore()
}

/// One frame of an exercise illustration, tinted with the ink colour.
///
/// With no picture (unmatched, none, unknown slug, not downloaded, offline)
/// it is an empty square of the same size: no placeholder, no spinner, so the
/// layout does not move if a picture arrives later.
///
/// The store comes from `\.artStore`; pass `store:` only in tests and previews.
public struct ExerciseFigure: View {
    private let art: ArtChoice
    private let frame: Int
    private let explicitStore: ArtStore?
    private let onLoad: ((Bool) -> Void)?

    @Environment(\.artStore) private var environmentStore
    @State private var image: UIImage?
    @State private var loadedKey: LoadKey?

    /// `onLoad` reports whether a load finished with a picture; nil keeps the figure silent.
    public init(art: ArtChoice, frame: Int = 1, store: ArtStore? = nil, onLoad: ((Bool) -> Void)? = nil) {
        self.art = art
        self.frame = frame
        self.explicitStore = store
        self.onLoad = onLoad
    }

    struct LoadKey: Equatable {
        let slug: String?
        let frame: Int
    }

    private var loadKey: LoadKey {
        if case .library(let slug) = art { return LoadKey(slug: slug, frame: frame) }
        return LoadKey(slug: nil, frame: frame)
    }

    static func resolveStore(explicit: ArtStore?, environment: ArtStore) -> ArtStore {
        explicit ?? environment
    }

    static func loadImage(slug: String?, frame: Int, store: ArtStore) async -> UIImage? {
        guard let slug, let data = await store.frame(slug: slug, frame: frame) else { return nil }
        return UIImage(data: data)
    }

    public var body: some View {
        ExerciseFigureCanvas(image: image)
            .task(id: loadKey) { await load() }
    }

    private func load() async {
        let key = loadKey
        // Clear only when the key really changed, so a row that scrolls back
        // into view keeps its figure instead of blinking.
        if loadedKey != key {
            image = nil
            loadedKey = key
        }
        guard image == nil else { return }
        let store = Self.resolveStore(explicit: explicitStore, environment: environmentStore)
        let loaded = await Self.loadImage(slug: key.slug, frame: key.frame, store: store)
        guard !Task.isCancelled else { return }
        image = loaded
        onLoad?(loaded != nil)
    }
}

/// The drawing half of `ExerciseFigure`: a pure function of its image.
/// The square is always present; the picture is only drawn over it.
struct ExerciseFigureCanvas: View {
    let image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColor.ink)
                .accessibilityHidden(true)
        }
    }
}
