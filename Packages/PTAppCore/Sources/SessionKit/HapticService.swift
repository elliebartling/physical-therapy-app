import UIKit

@MainActor
public final class HapticService {
    public enum Pattern { case lightTick, mediumTick, success }

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    public init() {
        light.prepare(); medium.prepare(); notification.prepare()
    }

    public func fire(_ pattern: Pattern) {
        switch pattern {
        case .lightTick: light.impactOccurred(); light.prepare()
        case .mediumTick: medium.impactOccurred(); medium.prepare()
        case .success: notification.notificationOccurred(.success); notification.prepare()
        }
    }
}
