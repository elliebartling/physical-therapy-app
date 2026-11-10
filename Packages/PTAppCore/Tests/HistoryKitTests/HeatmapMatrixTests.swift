import XCTest
import DataKit
@testable import HistoryKit

final class HeatmapMatrixTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    func test_monthMatrix_marksOnlyCompletedDays() {
        let june1 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day = { (d: Int) in self.cal.date(from: DateComponents(year: 2026, month: 6, day: d))! }
        let s = { (d: Date) -> SessionRecord in
            let r = SessionRecord(routineID: UUID(), startedAt: d); r.completedAt = d; return r
        }
        let sessions = [s(day(1)), s(day(2)), s(day(5))]

        let matrix = HeatmapMatrix.forMonth(containing: june1, sessions: sessions, calendar: cal)
        XCTAssertEqual(matrix.month, 6)
        XCTAssertEqual(matrix.year, 2026)
        XCTAssertEqual(matrix.completedDayNumbers, [1, 2, 5])
        XCTAssertEqual(matrix.daysInMonth, 30)
    }

    func test_monthMatrix_ignoresSessionsFromOtherMonths() {
        let june1 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let may30 = cal.date(from: DateComponents(year: 2026, month: 5, day: 30))!
        let july1 = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let s = { (d: Date) -> SessionRecord in
            let r = SessionRecord(routineID: UUID(), startedAt: d); r.completedAt = d; return r
        }
        let matrix = HeatmapMatrix.forMonth(containing: june1, sessions: [s(may30), s(july1)], calendar: cal)
        XCTAssertTrue(matrix.completedDayNumbers.isEmpty)
    }
}
