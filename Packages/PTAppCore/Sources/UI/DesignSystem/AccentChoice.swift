import SwiftUI

/// The user-selectable accent. Every option keeps `AppColor.onAccent` text at ≥4.5:1,
/// so text on an accent fill is always ink, never white.
public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case signal, sky, sun, mint, blossom, lilac

    public static let storageKey = "accentChoice"

    public var id: Self { self }

    public var name: String { rawValue.capitalized }

    public var hex: UInt32 {
        switch self {
        case .signal:  0xFF5A1F
        case .sky:     0x3FA9F5
        case .sun:     0xFFC531
        case .mint:    0x2BD99F
        case .blossom: 0xFF7EB6
        case .lilac:   0xA98BFF
        }
    }

    public var color: Color { Color(hex: hex) }
}

public extension Color {
    /// A large accent fill that ink text sits on. In dark mode ink is light, so the
    /// fill drops to a deep tone of the accent to keep that text above 4.5:1.
    func fieldTone(for scheme: ColorScheme) -> Color {
        scheme == .dark ? mix(with: .black, by: 0.55) : self
    }
}

public extension EnvironmentValues {
    @Entry var appAccent: Color = AccentChoice.signal.color
}
