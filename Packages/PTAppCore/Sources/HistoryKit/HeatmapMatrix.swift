import Foundation
import DataKit

public struct HeatmapMatrix: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let daysInMonth: Int
    public let completedDayNumbers: Set<Int>

    public init(year: Int, month: Int, daysInMonth: Int, completedDayNumbers: Set<Int>) {
        self.year = year
        self.month = month
        self.daysInMonth = daysInMonth
        self.completedDayNumbers = completedDayNumbers
    }

    public static func forMonth(
        containing date: Date,
        sessions: [SessionRecord],
        calendar: Calendar = .current
    ) -> HeatmapMatrix {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: comps)!
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!

        var completed = Set<Int>()
        for record in sessions {
            guard let completedAt = record.completedAt else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: completedAt)
            if c.year == comps.year, c.month == comps.month, let d = c.day {
                completed.insert(d)
            }
        }

        return HeatmapMatrix(
            year: comps.year!,
            month: comps.month!,
            daysInMonth: range.count,
            completedDayNumbers: completed
        )
    }
}
