import SwiftUI

public enum AppFont {
    public enum Weight { case regular, medium, bold }

    /// Labels, metadata and prescriptions ("3×12 L/R").
    public static func mono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "JetBrainsMono-Regular"
        case .medium:  name = "JetBrainsMono-Medium"
        case .bold:    name = "JetBrainsMono-Bold"
        }
        return Font.custom(name, fixedSize: size).monospacedDigit()
    }

    /// Titles, numbers and names: the system grotesk, set tight at the call site.
    public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }

    public static func body(_ size: CGFloat = 17) -> Font {
        Font.system(size: size, weight: .regular, design: .default)
    }
}

/// A small caps mono label, as in "01 — TODAY".
public struct SectionLabel: View {
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(AppFont.mono(11, weight: .medium))
            .tracking(0.7)
            .foregroundStyle(AppColor.inkSecondary)
    }
}
