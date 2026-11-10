import CoreGraphics

public enum AppSpacing {
    public static let unit: CGFloat = 8
    public static let screenPadding: CGFloat = 24
    public static func s(_ n: CGFloat) -> CGFloat { unit * n }
}
