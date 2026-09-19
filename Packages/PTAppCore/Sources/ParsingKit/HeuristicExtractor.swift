import Foundation

/// Never-failing fallback extractor: turns OCR lines into draft exercises
/// with cheap regex heuristics. Worst case a line becomes a name-only
/// draft with the default 3 x 10 target.
public struct HeuristicExtractor: RoutineExtractor {
    public var isAvailable: Bool { true }

    public init() {}

    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        let exercises = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !Self.isFurniture($0) }
            .map(Self.parseLine)
        return ParsedRoutine(name: "My routine", exercises: exercises)
    }

    // MARK: - Furniture

    static func isFurniture(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("www.") || lower.contains(".com") { return true }
        if lower.hasRegexMatch(#"^page\s*\d+"#) { return true }
        if lower.hasRegexMatch(#"\d{1,2}/\d{1,2}/\d{2,4}"#) { return true }
        if lower.hasRegexMatch(#"\(?\d{3}\)?[-. ]\d{3}[-. ]\d{4}"#) { return true }
        return false
    }

    // MARK: - Line parsing

    static func parseLine(_ raw: String) -> ParsedRoutine.ParsedExercise {
        var text = raw
        var reps: Int?
        var sets = 3
        var durationSec: Int?
        var restSec = 30

        text.stripFirstMatch(#"^\s*(?:\d+[\.\)]|[-•*])\s*"#)   // list markers: "1.", "2)", "-", "•"

        if let g = text.stripFirstMatch(#"\brest[:\s]*(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?|s)?\b"#) {
            restSec = seconds(g[1], unit: g[2])
        }

        if let g = text.stripFirstMatch(#"(\d+)\s*[x×]\s*(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?)\b"#) {
            sets = Int(g[1]) ?? 3                               // "3 x 45 sec"
            durationSec = seconds(g[2], unit: g[3])
        } else if let g = text.stripFirstMatch(#"(\d+)\s*[x×]\s*(\d+)"#) {
            sets = Int(g[1]) ?? 3                               // "3 x 10"
            reps = Int(g[2])
        } else if let g = text.stripFirstMatch(#"(\d+)\s*sets?(?:\s*of\s*(\d+))?"#) {
            sets = Int(g[1]) ?? 3                               // "3 sets of 12" / "2 sets"
            reps = g[2].isEmpty ? nil : Int(g[2])
        } else if let g = text.stripFirstMatch(#"[x×]\s*(\d+)"#) {
            reps = Int(g[1])                                    // bare "x15"
        }

        if reps == nil, let g = text.stripFirstMatch(#"(\d+)\s*reps?\b"#) {
            reps = Int(g[1])
        }
        if durationSec == nil, reps == nil, let g = text.stripFirstMatch(#"(?:hold\s*)?(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?)\b"#) {
            durationSec = seconds(g[1], unit: g[2])             // "hold 30 sec", "2 min"
        }
        if reps == nil, durationSec == nil { reps = 10 }        // floor: default 3 x 10

        let side = extractSide(from: &text)
        return .init(
            name: cleanName(text, fallback: raw),
            reps: reps, sets: sets, durationSec: durationSec,
            restSec: restSec, side: side, notes: ""
        )
    }

    static func extractSide(from text: inout String) -> String {
        let lower = text.lowercased()
        let side: String
        if lower.contains("alternat") {
            side = "alternating"
        } else if lower.contains("each side") || lower.contains("per side")
            || lower.contains("each leg") || lower.contains("per leg")
            || lower.contains("both") {
            side = "both"
        } else if lower.contains("left"), !lower.contains("right") {
            side = "left"
        } else if lower.contains("right"), !lower.contains("left") {
            side = "right"
        } else {
            side = "both"
        }
        text.stripFirstMatch(
            #"\b(each side|per side|each leg|per leg|both sides|alternating|alternate|left|right)\b"#
        )
        return side
    }

    static func cleanName(_ text: String, fallback: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"^[\s\-–—:,\.]+|[\s\-–—:,\.]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : cleaned
    }
}

private func seconds(_ number: String, unit: String) -> Int {
    let n = Int(number) ?? 0
    return unit.lowercased().hasPrefix("min") ? n * 60 : n
}

extension String {
    func hasRegexMatch(_ pattern: String) -> Bool {
        range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Removes the first match of `pattern` from the string and returns its
    /// capture groups (index 0 = whole match, unmatched groups = "").
    @discardableResult
    mutating func stripFirstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }
        let groups = (0..<m.numberOfRanges).map { i -> String in
            guard m.range(at: i).location != NSNotFound,
                  let r = Range(m.range(at: i), in: self) else { return "" }
            return String(self[r])
        }
        if let whole = Range(m.range, in: self) { removeSubrange(whole) }
        return groups
    }
}
