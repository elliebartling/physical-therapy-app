import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "PTAppCore", category: "app-icon")

/// Which design the home-screen icon uses. Each comes in every accent color.
public enum AppIconStyle: String, CaseIterable, Identifiable, Sendable {
    case rangeOfMotion, week

    public static let storageKey = "appIconStyle"
    public static let matchesAccentKey = "appIconMatchesAccent"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .rangeOfMotion: "Range of motion"
        case .week: "The week"
        }
    }

    /// The alternate icon to show, or nil for the primary icon (Range of motion in Signal).
    /// Names match the icon sets in the app's asset catalog (scripts/render-app-icons.mjs).
    public static func iconName(style: AppIconStyle, accent: AccentChoice, matchesAccent: Bool) -> String? {
        let color = matchesAccent ? accent : .signal
        if style == .rangeOfMotion, color == .signal { return nil }
        return "Icon-\(style.rawValue)-\(color.rawValue)"
    }

    /// Every alternate icon the app ships.
    public static var alternateIconNames: [String] {
        allCases.flatMap { style in
            AccentChoice.allCases.compactMap { iconName(style: style, accent: $0, matchesAccent: true) }
        }
    }
}

/// What can change the home-screen icon: the app in production, a fake in tests.
@MainActor
public protocol AppIconSetting: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ alternateIconName: String?) async throws
}

extension UIApplication: AppIconSetting {}

/// Keeps the home-screen icon in step with the chosen design and accent.
@MainActor
public final class AppIconController {
    private let app: () -> AppIconSetting

    /// `app` is resolved only when switching, so tests never touch UIApplication.
    public init(app: @escaping @MainActor () -> AppIconSetting = { UIApplication.shared }) {
        self.app = app
    }

    /// Switches the icon if it differs. Returns a message to show if switching failed.
    @discardableResult
    public func apply(style: AppIconStyle, accent: AccentChoice, matchesAccent: Bool) async -> String? {
        let app = app()
        guard app.supportsAlternateIcons else { return nil }
        let wanted = AppIconStyle.iconName(style: style, accent: accent, matchesAccent: matchesAccent)
        guard app.alternateIconName != wanted else { return nil }
        do {
            try await app.setAlternateIconName(wanted)
            return nil
        } catch {
            logger.error("Changing the app icon failed: \(String(describing: error), privacy: .public)")
            return "Couldn't change the app icon. Try again."
        }
    }
}

/// The icon artwork drawn live, for the picker in Settings (light appearance).
struct AppIconPreview: View {
    let style: AppIconStyle
    let accent: Color

    private let paper = Color(hex: 0xF3F2EE)
    private let ink = Color(hex: 0x111111)

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 100
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            switch style {
            case .rangeOfMotion:
                var wedge = Path()
                wedge.move(to: point(30, 72))
                wedge.addArc(center: point(30, 72), radius: 30 * unit,
                             startAngle: .degrees(-90), endAngle: .degrees(-45), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(accent))
                let arm = StrokeStyle(lineWidth: 6 * unit, lineCap: .round)
                context.stroke(Path { $0.move(to: point(30, 72)); $0.addLine(to: point(84, 72)) }, with: .color(ink), style: arm)
                context.stroke(Path { $0.move(to: point(30, 72)); $0.addLine(to: point(66, 36)) }, with: .color(ink), style: arm)
                let pivot = Path(ellipseIn: CGRect(x: 23 * unit, y: 65 * unit, width: 14 * unit, height: 14 * unit))
                context.fill(pivot, with: .color(paper))
                context.stroke(pivot, with: .color(ink), lineWidth: 4 * unit)
            case .week:
                for day in 0..<7 {
                    let x = 14 + CGFloat(day) * 10.6
                    let bar = Path(CGRect(x: x * unit, y: 30 * unit, width: 7.4 * unit, height: 40 * unit))
                    switch day {
                    case 0..<4: context.fill(bar, with: .color(ink))
                    case 4: context.fill(bar, with: .color(accent))
                    default:
                        let outline = Path(CGRect(x: (x + 0.75) * unit, y: 30.75 * unit,
                                                  width: 5.9 * unit, height: 38.5 * unit))
                        context.stroke(outline, with: .color(ink.opacity(0.45)), lineWidth: 1.5 * unit)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
