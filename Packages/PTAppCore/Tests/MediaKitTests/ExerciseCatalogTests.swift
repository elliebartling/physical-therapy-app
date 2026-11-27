import XCTest
@testable import MediaKit

final class ExerciseCatalogTests: XCTestCase {
    func test_bundledCatalogHasTheSubset() {
        let c = ExerciseCatalog.bundled
        XCTAssertEqual(c.entries.count, 142)
        XCTAssertEqual(c.entries.filter(\.isStretch).count, 14)
    }

    func test_lookupBySlug() {
        XCTAssertEqual(ExerciseCatalog.bundled.entry(slug: "bird-dog")?.name, "Bird Dog")
        XCTAssertNil(ExerciseCatalog.bundled.entry(slug: "bench-press"))
    }

    func test_slugsAreUnique() {
        let slugs = ExerciseCatalog.bundled.entries.map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count)
    }
}
