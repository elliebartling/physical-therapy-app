import XCTest

extension XCTestCase {
    /// A fresh, empty directory under the system temp directory, removed
    /// when the test finishes.
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not create temp directory: \(error)")
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
