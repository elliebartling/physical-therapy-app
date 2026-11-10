import SwiftUI

public enum AppFont {
    public enum Weight { case regular, medium, bold }

    public static func mono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "JetBrainsMono-Regular"
        case .medium:  name = "JetBrainsMono-Medium"
        case .bold:    name = "JetBrainsMono-Bold"
        }
        return Font.custom(name, fixedSize: size).monospacedDigit()
    }

    public static func body(_ size: CGFloat = 17) -> Font {
        Font.system(size: size, weight: .regular, design: .default)
    }
}
