# Finish v1 — Real Parsing + Device Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stubbed Foundation Models parser with a working extractor chain (on-device LLM when available, heuristic line parser as the never-failing floor), fix the setup failure path, and run the deferred on-device verification pass.

**Architecture:** `RoutineParser` walks an ordered list of `RoutineExtractor`s — skip unavailable ones, fall through on throw. `HeuristicExtractor` is pure regex text processing that never throws. `FoundationModelsExtractor` quarantines the `FoundationModels` import in one file behind a `@Generable` DTO. Only OCR failure reaches the UI.

**Tech Stack:** Swift 6, iOS 26+, FoundationModels framework (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`/`@Guide`), Vision OCR (existing), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-09-finish-v1-parsing-design.md` — read it first.

## Global Constraints

- iOS 26+ deployment target, Swift 6 strict concurrency — every type crossing an async boundary must be `Sendable`.
- No new package dependencies. No `Package.swift` changes.
- XCTest only (matches existing suite; do not introduce Swift Testing).
- Commit message style from git log: `feat(ParsingKit): …`, `fix(UI): …`, `test(UI): …`.
- ParsingKit must not import SwiftUI. `import FoundationModels` may appear ONLY in `FoundationModelsExtractor.swift`.
- Heuristic defaults (must match the LLM prompt): sets 3, reps 10 when nothing parses, restSec 30, side `"both"`. **Note:** the prompt in `FoundationModelsParser.instruction(for:)` currently defaults only `restSec` and `side` — it says nothing about sets or reps. Making these agree means editing the prompt too, not just the heuristic.
- Side strings must be one of `"both"`, `"left"`, `"right"`, `"alternating"` (they feed `Side(rawValue:)` in `ParsedRoutine.toRoutine()`).

## Running tests

**Corrected 2026-08-29.** The command previously written here did not work. `-scheme ParsingKit` (and `-scheme PTApp`) fail with `error: Scheme ParsingKit is not currently configured for the test action` — the generated project contains no `.xcscheme` files, and Xcode's implicit package schemes carry no test action. Tests run against the package's aggregate scheme, from `Packages/PTAppCore`:

```bash
cd Packages/PTAppCore && xcodebuild test \
  -scheme PTAppCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ParsingKitTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Verified: the full scheme runs all five bundles (33 tests, `** TEST SUCCEEDED **`), and `-only-testing` correctly narrows — e.g. `-only-testing:HistoryKitTests/StreakCalculatorTests` runs exactly 6. Swap `ParsingKitTests` for `UITests` for UI-layer tasks, or narrow to `-only-testing:ParsingKitTests/HeuristicExtractorTests`.

Once the orchestration work lands (`docs/superpowers/specs/2026-08-09-orchestration-setup-design.md`), this becomes `make test`; prefer that when it exists.

---

### Task 1: `HeuristicExtractor`

The never-failing floor: OCR lines → draft exercises via regex. Conforms to the *existing* `RoutineExtractor` protocol (the `isAvailable` addition comes in Task 2).

**Files:**
- Create: `Packages/PTAppCore/Sources/ParsingKit/HeuristicExtractor.swift`
- Test: `Packages/PTAppCore/Tests/ParsingKitTests/HeuristicExtractorTests.swift`

**Interfaces:**
- Consumes: `RoutineExtractor` protocol, `ParsedRoutine` / `ParsedRoutine.ParsedExercise` (existing).
- Produces: `public struct HeuristicExtractor: RoutineExtractor { public init(); func extract(fromOCRLines: [String]) async throws -> ParsedRoutine }` — never actually throws. Task 2 puts it at the end of the default chain.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/PTAppCore/Tests/ParsingKitTests/HeuristicExtractorTests.swift
import XCTest
import DataKit
@testable import ParsingKit

final class HeuristicExtractorTests: XCTestCase {
    private func parse(_ lines: [String]) async throws -> [ParsedRoutine.ParsedExercise] {
        try await HeuristicExtractor().extract(fromOCRLines: lines).exercises
    }

    // Quantity patterns

    func test_setsXReps() async throws {
        let ex = try await parse(["Squats 3 x 10"])[0]
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertNil(ex.durationSec)
    }

    func test_setsOfReps() async throws {
        let ex = try await parse(["Bridges 3 sets of 12"])[0]
        XCTAssertEqual(ex.name, "Bridges")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 12)
    }

    func test_bareReps_defaultsSets() async throws {
        let ex = try await parse(["Clamshells x15"])[0]
        XCTAssertEqual(ex.name, "Clamshells")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 15)
    }

    func test_timedHold() async throws {
        let ex = try await parse(["Plank hold 30 sec"])[0]
        XCTAssertEqual(ex.name, "Plank")
        XCTAssertEqual(ex.durationSec, 30)
        XCTAssertNil(ex.reps)
    }

    func test_setsXDuration() async throws {
        let ex = try await parse(["Wall sit 3 x 45 sec"])[0]
        XCTAssertEqual(ex.name, "Wall sit")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.durationSec, 45)
        XCTAssertNil(ex.reps)
    }

    func test_minutesConvertToSeconds() async throws {
        let ex = try await parse(["Hamstring stretch 2 min"])[0]
        XCTAssertEqual(ex.durationSec, 120)
    }

    // Rest

    func test_restSeconds() async throws {
        let ex = try await parse(["Squats 3 x 10 rest 45 sec"])[0]
        XCTAssertEqual(ex.restSec, 45)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.name, "Squats")
    }

    func test_restDefaults30() async throws {
        let ex = try await parse(["Squats 3 x 10"])[0]
        XCTAssertEqual(ex.restSec, 30)
    }

    // Sides

    func test_eachSide_mapsToBoth_andStripsMarker() async throws {
        let ex = try await parse(["Leg raises 3 x 10 each side"])[0]
        XCTAssertEqual(ex.side, "both")
        XCTAssertEqual(ex.name, "Leg raises")
    }

    func test_alternating() async throws {
        let ex = try await parse(["Alternating lunges 3 x 10"])[0]
        XCTAssertEqual(ex.side, "alternating")
    }

    func test_singleSide() async throws {
        let ex = try await parse(["Left leg raises 3 x 10"])[0]
        XCTAssertEqual(ex.side, "left")
        XCTAssertEqual(ex.name, "leg raises")
    }

    // Furniture + floor

    func test_furnitureLinesDropped() async throws {
        let exs = try await parse([
            "Lakeview Physical Therapy - www.lakeviewpt.com",
            "Printed 06/14/2026",
            "Page 1",
            "(555) 123-4567",
            "Squats 3 x 10",
        ])
        XCTAssertEqual(exs.count, 1)
        XCTAssertEqual(exs[0].name, "Squats")
    }

    func test_unmatchedLine_becomesDefaultDraft() async throws {
        let ex = try await parse(["Squats"])[0]
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.restSec, 30)
        XCTAssertEqual(ex.side, "both")
    }

    func test_listMarkersStripped() async throws {
        let exs = try await parse(["1. Squats 3 x 10", "- Bridges 2 x 8"])
        XCTAssertEqual(exs[0].name, "Squats")
        XCTAssertEqual(exs[1].name, "Bridges")
    }

    // Whole messy handout

    func test_messyHandout() async throws {
        let exs = try await parse([
            "Knee Rehab - Week 3",
            "1. Mini squats 3 x 10, rest 30 sec",
            "2. Straight leg raise x10 each leg",
            "3. Wall sit hold 45 seconds",
            "Page 1 of 1",
        ])
        XCTAssertEqual(exs.count, 4)   // furniture "Page 1 of 1" dropped; title kept as a draft the user deletes
        XCTAssertEqual(exs[1].name, "Mini squats")
        XCTAssertEqual(exs[1].reps, 10)
        XCTAssertEqual(exs[2].reps, 10)
        XCTAssertEqual(exs[2].side, "both")
        XCTAssertEqual(exs[3].durationSec, 45)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Expected: compile error — `HeuristicExtractor` not defined.

- [ ] **Step 3: Implement**

```swift
// Packages/PTAppCore/Sources/ParsingKit/HeuristicExtractor.swift
import Foundation

/// Never-failing fallback extractor: turns OCR lines into draft exercises
/// with cheap regex heuristics. Worst case a line becomes a name-only
/// draft with the default 3 x 10 target.
public struct HeuristicExtractor: RoutineExtractor {
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

        if durationSec == nil, let g = text.stripFirstMatch(#"(?:hold\s*)?(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?)\b"#) {
            durationSec = seconds(g[1], unit: g[2])             // "hold 30 sec", "2 min"
            reps = nil
        }
        if reps == nil, durationSec == nil, let g = text.stripFirstMatch(#"(\d+)\s*reps?\b"#) {
            reps = Int(g[1])
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
```

Note: `hasRegexMatch`/`stripFirstMatch` are internal on purpose — Task 4's view-model test target imports ParsingKit non-`@testable`, and nothing outside ParsingKit needs them.

- [ ] **Step 4: Run tests to verify pass**

Run the ParsingKit test command from "Running tests" with `-only-testing:ParsingKitTests/HeuristicExtractorTests`. Expected: all PASS. If a regex disagrees with a test, fix the implementation, not the test — the tests encode the spec's pattern families.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/ParsingKit/HeuristicExtractor.swift \
        Packages/PTAppCore/Tests/ParsingKitTests/HeuristicExtractorTests.swift
git commit -m "feat(ParsingKit): HeuristicExtractor — regex fallback parser"
```

---

### Task 2: Extractor chain in `RoutineParser`

Protocol gets `isAvailable`; parser walks an ordered extractor list; OCR-empty becomes a typed error. Protocol + `StubExtractor` move to a new file so Task 3 can rewrite the Foundation Models file wholesale.

**Files:**
- Create: `Packages/PTAppCore/Sources/ParsingKit/RoutineExtractor.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/RoutineParser.swift` (full rewrite below)
- Modify: `Packages/PTAppCore/Sources/ParsingKit/FoundationModelsParser.swift` (delete the protocol + `StubExtractor` declarations from it; keep `FoundationModelsParser` itself untouched)
- Modify: `Packages/PTAppCore/Tests/ParsingKitTests/RoutineParserTests.swift`
- Modify: `Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift:15` (call-site signature change)

**Interfaces:**
- Consumes: `HeuristicExtractor` (Task 1), existing `FoundationModelsParser`, `OCRService.recognizeLines(in:) async throws -> [String]`.
- Produces:
  - `RoutineExtractor` gains `var isAvailable: Bool { get }` with a protocol-extension default of `true`.
  - `public enum ParsingError: Error, LocalizedError, Equatable { case noTextFound, allExtractorsFailed }`
  - `RoutineParser.init(ocr: OCRService = .init(), extractors: [RoutineExtractor] = [FoundationModelsParser(), HeuristicExtractor()])` — the old `extractor:` (singular) label is gone; Task 3 swaps the first default element.
  - `RoutineParser.parse(_: UIImage) async throws -> ParsedRoutine` throws only `ParsingError.noTextFound` in practice (heuristic floor catches the rest).

- [ ] **Step 1: Write the failing tests**

Replace `Packages/PTAppCore/Tests/ParsingKitTests/RoutineParserTests.swift` with:

```swift
import XCTest
import UIKit
import DataKit
@testable import ParsingKit

private struct ThrowingExtractor: RoutineExtractor {
    struct Failure: Error {}
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine { throw Failure() }
}

private struct UnavailableExtractor: RoutineExtractor {
    var isAvailable: Bool { false }
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        XCTFail("unavailable extractor must never be called")
        return ParsedRoutine(name: "unavailable", exercises: [])
    }
}

final class RoutineParserTests: XCTestCase {
    private let canned = ParsedRoutine(name: "Knee", exercises: [
        .init(name: "Squat", reps: 12, sets: 3, durationSec: nil, restSec: 30, side: "both", notes: "")
    ])

    func test_combinesOCRAndExtractor() async throws {
        let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
        let url = Bundle.module.url(forResource: "handout_clean", withExtension: "png")!
        let image = UIImage(contentsOfFile: url.path)!
        let parsed = try await parser.parse(image)
        XCTAssertEqual(parsed, canned)
    }

    func test_chain_skipsUnavailableExtractor() async throws {
        let parser = RoutineParser(extractors: [UnavailableExtractor(), StubExtractor(result: canned)])
        let out = try await parser.extract(fromOCRLines: ["anything"])
        XCTAssertEqual(out, canned)
    }

    func test_chain_fallsThroughOnThrow() async throws {
        let parser = RoutineParser(extractors: [ThrowingExtractor(), StubExtractor(result: canned)])
        let out = try await parser.extract(fromOCRLines: ["anything"])
        XCTAssertEqual(out, canned)
    }

    func test_chain_allFail_throwsLastError() async {
        let parser = RoutineParser(extractors: [ThrowingExtractor()])
        do {
            _ = try await parser.extract(fromOCRLines: ["anything"])
            XCTFail("expected throw")
        } catch is ThrowingExtractor.Failure {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_parse_blankImage_throwsNoTextFound() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let blank = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let parser = RoutineParser(extractors: [StubExtractor(result: canned)])
        do {
            _ = try await parser.parse(blank)
            XCTFail("expected throw")
        } catch let e as ParsingError {
            XCTAssertEqual(e, .noTextFound)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Expected: compile errors — `extractors:` label and `ParsingError` don't exist yet.

- [ ] **Step 3: Implement**

Create `Packages/PTAppCore/Sources/ParsingKit/RoutineExtractor.swift`:

```swift
import Foundation

public protocol RoutineExtractor: Sendable {
    /// Whether this extractor can run right now (e.g. on-device model present).
    /// Defaults to true.
    var isAvailable: Bool { get }
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine
}

public extension RoutineExtractor {
    var isAvailable: Bool { true }
}

public enum ParsingError: Error, LocalizedError, Equatable {
    case noTextFound
    case allExtractorsFailed

    public var errorDescription: String? {
        switch self {
        case .noTextFound:
            "No readable text was found in the photo."
        case .allExtractorsFailed:
            "Couldn't turn the text into a routine."
        }
    }
}

/// Test double — returns a canned ParsedRoutine.
public struct StubExtractor: RoutineExtractor {
    public let result: ParsedRoutine
    public init(result: ParsedRoutine) { self.result = result }
    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine { result }
}
```

Replace `Packages/PTAppCore/Sources/ParsingKit/RoutineParser.swift` with:

```swift
import Foundation
import UIKit

public struct RoutineParser: Sendable {
    public let ocr: OCRService
    public let extractors: [RoutineExtractor]

    public init(
        ocr: OCRService = .init(),
        extractors: [RoutineExtractor] = [FoundationModelsParser(), HeuristicExtractor()]
    ) {
        self.ocr = ocr
        self.extractors = extractors
    }

    public func parse(_ image: UIImage) async throws -> ParsedRoutine {
        let lines = try await ocr.recognizeLines(in: image)
        guard !lines.isEmpty else { throw ParsingError.noTextFound }
        return try await extract(fromOCRLines: lines)
    }

    /// Walks the chain: skips unavailable extractors, falls through on throw.
    func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        var lastError: Error = ParsingError.allExtractorsFailed
        for extractor in extractors where extractor.isAvailable {
            do { return try await extractor.extract(fromOCRLines: lines) }
            catch { lastError = error }
        }
        throw lastError
    }
}
```

In `FoundationModelsParser.swift`, delete the `RoutineExtractor` protocol declaration and the `StubExtractor` struct (both now live in `RoutineExtractor.swift`). Keep the `FoundationModelsParser` struct exactly as is.

In `Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift`, change line 15 from

```swift
let parser = RoutineParser(ocr: OCRService(), extractor: StubExtractor(result: canned))
```

to

```swift
let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
```

- [ ] **Step 4: Run tests to verify pass**

Run ParsingKitTests (all of them — the old `FoundationModelsParserTests` must still pass) and `UITests/SetupViewModelTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/ParsingKit/ Packages/PTAppCore/Tests/
git commit -m "feat(ParsingKit): extractor chain in RoutineParser + ParsingError"
```

---

### Task 3: `FoundationModelsExtractor`

The real on-device LLM extractor. One file owns `import FoundationModels`; a private `@Generable` DTO maps back to `ParsedRoutine` so domain types never depend on the framework.

**Files:**
- Rename + rewrite: `Packages/PTAppCore/Sources/ParsingKit/FoundationModelsParser.swift` → `FoundationModelsExtractor.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/RoutineParser.swift:10` (default chain)
- Rename + rewrite: `Packages/PTAppCore/Tests/ParsingKitTests/FoundationModelsParserTests.swift` → `FoundationModelsExtractorTests.swift`

**Interfaces:**
- Consumes: `RoutineExtractor` + `ParsingError` (Task 2), `ParsedRoutine`.
- Produces: `public struct FoundationModelsExtractor: RoutineExtractor` with `isAvailable` reflecting `SystemLanguageModel.default.availability`. The type `FoundationModelsParser` ceases to exist — the default chain becomes `[FoundationModelsExtractor(), HeuristicExtractor()]`.

- [ ] **Step 0: Verify the FoundationModels API surface against Apple's docs**

The original plan flagged these symbols as unverified. Before writing code, open https://developer.apple.com/documentation/foundationmodels and confirm: `SystemLanguageModel.default.availability` (an enum with `.available` / `.unavailable(reason)`), `LanguageModelSession(instructions:)`, `session.respond(to:generating:)` returning a response whose `.content` is the generated type, and the `@Generable` / `@Guide(description:)` macros. If any differ, adapt the code in Step 3 to the real API — the DTO-mapping shape and `isAvailable` contract must not change.

- [ ] **Step 1: Write the failing tests**

```bash
git mv Packages/PTAppCore/Tests/ParsingKitTests/FoundationModelsParserTests.swift \
       Packages/PTAppCore/Tests/ParsingKitTests/FoundationModelsExtractorTests.swift
```

Replace its contents with:

```swift
import XCTest
import DataKit
@testable import ParsingKit

final class FoundationModelsExtractorTests: XCTestCase {
    func test_dtoMapping_repsBased() {
        let dto = GenerableExercise(
            name: "Squats", reps: 10, sets: 3, durationSec: nil,
            restSec: 45, side: "left", notes: "slow tempo"
        )
        let ex = dto.toParsedExercise()
        XCTAssertEqual(ex.name, "Squats")
        XCTAssertEqual(ex.reps, 10)
        XCTAssertEqual(ex.sets, 3)
        XCTAssertNil(ex.durationSec)
        XCTAssertEqual(ex.restSec, 45)
        XCTAssertEqual(ex.side, "left")
        XCTAssertEqual(ex.notes, "slow tempo")
    }

    func test_dtoMapping_timeBased_andRoutineName() {
        let dto = GenerableRoutine(name: "Knee rehab", exercises: [
            GenerableExercise(name: "Plank", reps: nil, sets: 2, durationSec: 30,
                              restSec: 30, side: "both", notes: "")
        ])
        let parsed = dto.toParsedRoutine()
        XCTAssertEqual(parsed.name, "Knee rehab")
        XCTAssertEqual(parsed.exercises[0].durationSec, 30)
        XCTAssertNil(parsed.exercises[0].reps)
    }

    func test_dtoMapping_invalidSide_normalizesToBoth() {
        let dto = GenerableExercise(name: "X", reps: 5, sets: 1, durationSec: nil,
                                    restSec: 0, side: "EACH SIDE??", notes: "")
        XCTAssertEqual(dto.toParsedExercise().side, "both")
    }

    func test_isAvailable_returnsWithoutCrashing() {
        _ = FoundationModelsExtractor().isAvailable
    }

    /// Live on-device test. Skips wherever the model is unavailable (CI, most
    /// simulators). Run manually on the Apple Intelligence iPhone.
    func test_live_extractsFromSampleLines() async throws {
        let extractor = FoundationModelsExtractor()
        guard extractor.isAvailable else {
            throw XCTSkip("Foundation Models unavailable on this destination")
        }
        let parsed = try await extractor.extract(fromOCRLines: [
            "Knee Rehab Program",
            "1. Mini squats 3 x 10, rest 45 sec",
            "2. Plank: hold 30 seconds, 3 sets",
            "3. Straight leg raise x10 each leg",
        ])
        XCTAssertGreaterThanOrEqual(parsed.exercises.count, 3)
        XCTAssertTrue(parsed.exercises.contains { $0.durationSec != nil })
    }
}
```

(The old `test_stubExtractor_returnsConfiguredRoutine` is deleted — `StubExtractor` is exercised throughout `RoutineParserTests` now. `test_foundationModelsParser_throwsUntilWired` is obsolete by design.)

- [ ] **Step 2: Run to verify failure**

Expected: compile errors — `GenerableExercise`, `GenerableRoutine`, `FoundationModelsExtractor` not defined.

- [ ] **Step 3: Implement**

```bash
git mv Packages/PTAppCore/Sources/ParsingKit/FoundationModelsParser.swift \
       Packages/PTAppCore/Sources/ParsingKit/FoundationModelsExtractor.swift
```

Replace its contents with (adjusting symbols per Step 0 findings):

```swift
import Foundation
import FoundationModels

/// On-device LLM extractor. The only file in the package allowed to
/// import FoundationModels.
public struct FoundationModelsExtractor: RoutineExtractor {
    public init() {}

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func extract(fromOCRLines lines: [String]) async throws -> ParsedRoutine {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: lines.joined(separator: "\n"),
            generating: GenerableRoutine.self
        )
        return response.content.toParsedRoutine()
    }

    static let instructions = """
    You will be given OCR lines from a physical therapy exercise handout.
    Extract a structured routine. For each exercise capture: name, reps OR durationSec, \
    sets, restSec, side (one of: both, left, right, alternating), and notes.
    Default restSec to 30 and side to "both" if not stated. Ignore page furniture \
    such as dates, clinic names, page numbers, and contact details.
    """
}

@Generable
struct GenerableRoutine {
    @Guide(description: "Short name for the routine, e.g. 'Knee rehab'")
    var name: String
    var exercises: [GenerableExercise]

    func toParsedRoutine() -> ParsedRoutine {
        ParsedRoutine(name: name, exercises: exercises.map { $0.toParsedExercise() })
    }
}

@Generable
struct GenerableExercise {
    @Guide(description: "Exercise name")
    var name: String
    @Guide(description: "Repetitions per set; omit when the exercise is time-based")
    var reps: Int?
    @Guide(description: "Number of sets; 3 when not stated")
    var sets: Int
    @Guide(description: "Hold duration in seconds; omit when rep-based")
    var durationSec: Int?
    @Guide(description: "Rest in seconds between sets; 30 when not stated")
    var restSec: Int
    @Guide(description: "Exactly one of: both, left, right, alternating")
    var side: String
    @Guide(description: "Extra instructions; empty string when none")
    var notes: String

    func toParsedExercise() -> ParsedRoutine.ParsedExercise {
        let validSides = ["both", "left", "right", "alternating"]
        let normalizedSide = side.lowercased().trimmingCharacters(in: .whitespaces)
        return .init(
            name: name,
            reps: reps,
            sets: max(1, sets),
            durationSec: durationSec,
            restSec: max(0, restSec),
            side: validSides.contains(normalizedSide) ? normalizedSide : "both",
            notes: notes
        )
    }
}
```

In `RoutineParser.swift`, change the default:

```swift
extractors: [RoutineExtractor] = [FoundationModelsExtractor(), HeuristicExtractor()]
```

- [ ] **Step 4: Run tests to verify pass**

Run all ParsingKitTests on the simulator. Expected: everything PASSES, with `test_live_extractsFromSampleLines` either passing or skipping (Apple-silicon simulators with Apple Intelligence enabled on the Mac can run the model; otherwise it skips — both outcomes are green).

- [ ] **Step 5: Run the live test on the physical iPhone**

Connect the Apple Intelligence iPhone, then:

```bash
cd Packages/PTAppCore && xcodebuild test \
  -scheme PTAppCore-Package \
  -destination 'platform=iOS,name=YOUR_IPHONE_NAME' \
  -only-testing:ParsingKitTests/FoundationModelsExtractorTests/test_live_extractsFromSampleLines
```

(`xcrun xctrace list devices` shows the device name; or run the single test from Xcode's test navigator with the device selected.) Expected: PASS, not skip. If it skips, Apple Intelligence isn't enabled in Settings or the model is still downloading — resolve and rerun.

- [ ] **Step 6: Commit**

```bash
git add -A Packages/PTAppCore/
git commit -m "feat(ParsingKit): FoundationModelsExtractor — real on-device LLM extraction"
```

---

### Task 4: `SetupViewModel` failure path

`.failed` now only fires for true OCR failure; give it actionable copy instead of a raw `localizedDescription`. The pre-filled-editor fallback needs no view-model change — the chain guarantees it.

**Files:**
- Modify: `Packages/PTAppCore/Sources/UI/Setup/SetupViewModel.swift:31-34`
- Test: `Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift`

**Interfaces:**
- Consumes: `RoutineParser(extractors:)` and `ParsingError` (Task 2).
- Produces: no signature changes; `Phase.failed(String)` payload becomes fixed user-facing copy.

- [ ] **Step 1: Write the failing test**

Append to `SetupViewModelTests`:

```swift
func test_parse_unreadablePhoto_failsWithActionableMessage() async throws {
    let container = try ModelContainerFactory.inMemory()
    let repo = RoutineRepository(context: container.mainContext)
    let canned = ParsedRoutine(name: "Knee", exercises: [])
    let parser = RoutineParser(ocr: OCRService(), extractors: [StubExtractor(result: canned)])
    let vm = SetupViewModel(routineRepo: repo, parser: parser)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
    let blank = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    await vm.parse(blank)

    guard case .failed(let message) = vm.phase else {
        return XCTFail("expected .failed, got \(vm.phase)")
    }
    XCTAssertTrue(message.contains("light"))
    _ = container
}
```

- [ ] **Step 2: Run to verify failure**

Run `UITests/SetupViewModelTests`. Expected: FAIL — the message is currently `ParsingError.noTextFound`'s `localizedDescription`, which doesn't contain "light".

- [ ] **Step 3: Implement**

In `SetupViewModel.parse`, replace the catch block:

```swift
} catch {
    draft = .init(name: "My routine", exercises: [])
    phase = .failed("We couldn't read that photo. Try again with more light and the page held flat — or enter your routine manually.")
}
```

- [ ] **Step 4: Run tests to verify pass**

Run all `UITests`. Expected: PASS (including the two existing snapshot tests — the failure copy isn't asserted there, but confirm nothing else broke).

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Setup/SetupViewModel.swift \
        Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift
git commit -m "fix(UI): actionable copy on OCR failure in SetupViewModel"
```

---

### Task 5: On-device verification pass (Task 41, adapted)

Manual, human-run. Build the `PTApp` scheme to the Apple Intelligence iPhone from Xcode and work through the checklist. Record each result in a verification log as you go.

**Files:**
- Create: `docs/superpowers/verification/2026-08-09-v1-device-verification.md` (log of results)

- [ ] **Step 1: Real-handout scan (LLM path)** — Scan a real or printed PT handout. Verify: parse completes, drafts match the handout closely (names, reps/sets/holds, sides), editing and saving works, routine is active on Home. Note in the log which extractor path ran (if drafts are suspiciously literal per-line, the heuristic floor ran — check Apple Intelligence is enabled and rerun).
- [ ] **Step 2: Heuristic fallback** — Settings → Apple Intelligence off (or Airplane-mode fresh boot before the model loads is not reliable — use the toggle). Scan the same handout. Verify: drafts still appear (rougher is fine), editor opens, no error screen. Re-enable Apple Intelligence after.
- [ ] **Step 3: Unreadable photo** — Scan a blank page or the floor. Verify: failure screen with the "more light" copy and a working "Enter manually" button.
- [ ] **Step 4: Camera permission denied** — Delete + reinstall the app, deny camera permission. Verify manual-entry path still sets up a routine.
- [ ] **Step 5: Full session phone-down** — Run the full routine with the phone face-down on a mat. Verify audio + haptic cues land on every set start, rest, side switch, exercise change, and completion.
- [ ] **Step 6: Pause + lock + resume** — Mid-session, lock the phone 30s, unlock. Verify the engine resumes in place.
- [ ] **Step 7: Background timeout** — Background the app >10 min mid-session, relaunch. Verify the session was saved as partial (`completedAt == nil`) and Home is in a sane state.
- [ ] **Step 8: Streak + heatmap** — After completing a session, verify streak increments and today's heatmap cell fills.
- [ ] **Step 9: Reminder** — Enable the reminder for 2 minutes out, background the app. Verify the notification fires; disable and verify silence.
- [ ] **Step 10 (deferred): iCloud sync** — Requires a second device on the same Apple ID. Leave marked deferred in the log with today's date.
- [ ] **Step 11: Commit the log**

```bash
git add docs/superpowers/verification/2026-08-09-v1-device-verification.md
git commit -m "docs: v1 on-device verification log"
```
