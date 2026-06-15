import SwiftUI
import UIKit

public enum AppColor {
    public static let surface  = Color(light: 0xFFFFFF, dark: 0x0A0A0A)
    public static let text     = Color(light: 0x0A0A0A, dark: 0xFAFAFA)
    public static let hairline = Color(light: 0xE5E5E5, dark: 0x222222)
    public static let accent   = Color(hex: 0xFFD60A) // safety yellow
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
