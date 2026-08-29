import Foundation

public enum Format {
    /// "45s", "2m", "1m 30s"
    public static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    /// "0:45", "12:03"
    public static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
