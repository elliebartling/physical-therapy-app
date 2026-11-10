import SwiftUI

/// The one primary action on a screen: an ink-tinted Liquid Glass capsule.
public struct InkGlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColor.surface)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(AppColor.ink.opacity(0.85)).interactive(), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Toolbar-sized clear glass circle for icon-only buttons. Give each one an accessibility label.
public struct GlassCircleButtonStyle: ButtonStyle {
    private let diameter: CGFloat

    public init(diameter: CGFloat = 44) { self.diameter = diameter }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColor.ink)
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
