import Foundation
import UIKit

public struct RoutineParser: Sendable {
    public let ocr: OCRService
    public let extractor: RoutineExtractor

    public init(ocr: OCRService = .init(), extractor: RoutineExtractor = FoundationModelsParser()) {
        self.ocr = ocr
        self.extractor = extractor
    }

    public func parse(_ image: UIImage) async throws -> ParsedRoutine {
        let lines = try await ocr.recognizeLines(in: image)
        return try await extractor.extract(fromOCRLines: lines)
    }
}
