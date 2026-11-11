import Foundation

/// Splits a dictated description into one candidate exercise per sentence or line.
public enum TranscriptSegmenter {
    public static func lines(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
