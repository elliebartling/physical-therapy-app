import Foundation
import Vision

enum OCRService {
    /// Runs accurate on-device text recognition over one screenshot.
    static func recognizeText(in imageData: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
