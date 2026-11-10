import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var reminderEnabled = false
    public var reminderTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now

    private let scheduler = NotificationScheduler()

    public init() {}

    public func applyReminder() async {
        if reminderEnabled {
            do {
                guard try await scheduler.requestAuthorization() else { reminderEnabled = false; return }
                let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                try await scheduler.schedule(at: comps)
            } catch {
                reminderEnabled = false
            }
        } else {
            scheduler.cancel()
        }
    }
}
