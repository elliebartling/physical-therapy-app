import SwiftUI
import UIKit

public enum AppColor {
    public static let surface      = Color(light: 0xF3F2EE, dark: 0x0E0E0D) // paper
    public static let ink          = Color(light: 0x111111, dark: 0xF3F2EE)
    public static let inkSecondary = Color(light: 0x57564F, dark: 0xA3A29B)
    public static let hairline     = Color(light: 0xD9D8D3, dark: 0x2A2A27)
    /// Text drawn on an accent fill. Every `AccentChoice` keeps ≥4.5:1 against it.
    public static let onAccent     = Color(hex: 0x111111)
}

public extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}
