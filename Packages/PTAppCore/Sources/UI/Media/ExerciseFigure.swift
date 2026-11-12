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
public struct ExerciseFigure: View {
    private let art: ArtChoice
    private let frame: Int
    private let store: ArtStore

    @State private var image: UIImage?

    public init(art: ArtChoice, frame: Int = 1, store: ArtStore) {
        self.art = art
        self.frame = frame
        self.store = store
    }

    private struct LoadKey: Equatable {
        let slug: String?
        let frame: Int
    }

    private var loadKey: LoadKey {
        if case .library(let slug) = art { return LoadKey(slug: slug, frame: frame) }
        return LoadKey(slug: nil, frame: frame)
    }

    public var body: some View {
        // The square is always present; the picture is only drawn over it.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .accessibilityHidden(true)
            .task(id: loadKey) { await load() }
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColor.ink)
        }
    }

    private func load() async {
        image = nil
        guard let slug = loadKey.slug,
              let data = await store.frame(slug: slug, frame: frame),
              !Task.isCancelled else { return }
        image = UIImage(data: data)
    }
}
