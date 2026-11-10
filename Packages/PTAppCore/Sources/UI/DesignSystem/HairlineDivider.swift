import SwiftUI
import UIKit

public struct HairlineDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(AppColor.hairline)
            .frame(height: 1 / UIScreen.main.scale)
    }
}

/// A solid ink rule: 2pt under the masthead, 1pt between sections.
public struct InkRule: View {
    private let weight: CGFloat

    public init(weight: CGFloat = 1) { self.weight = weight }

    public var body: some View {
        Rectangle()
            .fill(AppColor.ink)
            .frame(height: weight)
            .accessibilityHidden(true)
    }
}
