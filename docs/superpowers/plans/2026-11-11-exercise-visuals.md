# Mend Exercise Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every exercise a still line-art figure that the user can correct at any time, and carry the PT sheet's own how-to text through to where they read it.

**Architecture:** A new `MediaKit` target owns a bundled catalogue of 142 exercises, a two-stage matcher (local scoring, then on-device ranking), and an art store that downloads frame PNGs from jsDelivr on first use and caches them in Application Support. `ArtChoice` goes on `Exercise` and on `ParsedRoutine.ParsedExercise`, and rides the existing `ParsedRoutine(routine:)` ⇄ `apply(to:)` round-trip — so one picture control in `ExerciseEditorView` serves both import review and after-save correction. No new screens: Today's list, the session screen, `ExerciseProgressView` and the editor all exist.

**Tech Stack:** Swift 6.2, iOS 26, SwiftUI, SwiftData, FoundationModels, XCTest, ViewInspector.

**Spec:** `docs/superpowers/specs/2026-11-11-exercise-visuals-design.md`

**One deliberate departure from the spec.** The spec proposes storing the chosen picture as `library://<slug>/<frame>` inside `Asset.urlString` on `Exercise.media`. This plan uses a dedicated `ArtChoice` on `Exercise` instead, because `media` is an unordered `[Asset]` with no role field — nothing would mark which asset is *selected*, and "never matched" could not be told apart from "user chose none". `ArtChoice` makes all three states explicit and follows the `sideRaw`/`side` and `phaseStorage`/`phase` patterns already in the models. `Asset` and `Exercise.media` stay unused, for the user-supplied images of a later phase.

## Global Constraints

- `@Observable` classes with `@State`/`@Bindable`. Never `ObservableObject`, `@StateObject`, `@Published`.
- `NavigationStack`, never `NavigationView`.
- `async/await` and structured concurrency only. No GCD, no completion handlers. Anything crossing an async boundary is `Sendable`. Strict-concurrency warnings stay at zero.
- No force-unwraps (`!`, `try!`) outside tests.
- Value types first. Structs and enums unless identity or observation demands a class.
- Semantic colours (`AppColor`), `AppFont` text styles, SF Symbols. Must work in dark mode and at accessibility text sizes.
- Accessibility labels on symbol-only buttons; decorative figures are hidden from VoiceOver.
- XCTest, not Swift Testing. ViewInspector for view tests.
- **No new package dependencies.** Everything here uses Foundation, SwiftUI, SwiftData, FoundationModels.
- No APIs above iOS 26 without `#available` gating.
- App code lives in `Packages/PTAppCore`. Never edit the generated `.xcodeproj`. App-target settings go in `App/project.yml`.
- Asset base URL, used verbatim: `https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/assets/<slug>/frame-<n>.png`
- Attribution text, used verbatim: `Exercise illustrations by Bryl Lim, licensed CC BY-SA 4.0. Derived from Everkinetic.`

**Existing interfaces this plan builds on** — read before assuming any shape:

- `ParsedRoutine+Editing.swift`: `ParsedRoutine.init(routine:)`, `ParsedRoutine.apply(to:) -> [Exercise]`, `ParsedExercise.init(exercise:)`, `ParsedExercise.target`, `ParsedExercise.resolvedSide`.
- `RoutineRepository`: `save(_:)`, `fetchActive()`, `fetchAll()`, `saveEdits(to:removing:)`, `replaceActive(with:)`.
- `RoutineEditorView(viewModel:title:onSave:onCancel:)`; `ExerciseEditorView(exercise:)` with `navigationTitle("Exercise")` and sections name / Target / Rest / Side / Notes.
- `EditRoutineView(routine:repo:onDone:)` → `EditRoutineViewModel.save()`.
- `HomeView(viewModel:onStart:onSettings:onSetup:onEditRoutine:)`; `ExerciseRowView(row:)` is private in `HomeView.swift`.
- `ProgressScreen.Route.exercise(UUID)` → `ExerciseProgressView(viewModel:exerciseID:)`; `ProgressViewModel.exercise(id:) -> ExerciseRow?` with `name`, `prescription`, `stats`.
- `SessionViewModel.currentNotes` is rendered beside the running timer in `SessionView`.

**Test command** (all suites):

```bash
cd Packages/PTAppCore && xcodebuild test -scheme PTAppCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Single suite, substitute as needed: append `-only-testing:PTAppCore-Package:MediaKitTests`.

## Review Focus

Five conditions the spec implies that no task's happy path exercises. Each has a test pinned to the task that owns the code.

1. **First launch with no network.** Art never downloads; every exercise shows no picture, nothing crashes, and a later launch with network fills them in. (Task 6)
2. **`SystemLanguageModel` unavailable.** Matching degrades to stage 1 alone and the confidence floor still applies, so uncovered exercises get no picture rather than the least-bad slug. (Task 5)
3. **A stored slug that is no longer in the catalogue** (subset changed between app versions). Resolves to no picture, not a crash or a broken image. (Task 6)
4. **Garbage OCR as an exercise name** — empty string, page furniture, a date. The matcher returns no match rather than an arbitrary slug. (Task 4)
5. **Editing a saved routine must not drop the picture.** The `ParsedRoutine(routine:)` → edit → `apply(to:)` round-trip preserves `art` on exercises the user never touched. (Task 2)

---

### Task 1: `ArtChoice` on the data model

**Files:**
- Create: `Packages/PTAppCore/Sources/DataKit/Models/ArtChoice.swift`
- Modify: `Packages/PTAppCore/Sources/DataKit/Models/Exercise.swift`
- Test: `Packages/PTAppCore/Tests/DataKitTests/ArtChoiceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum ArtChoice: Equatable, Sendable, Codable { case unmatched; case library(slug: String); case none }`, with `public var rawValue: String` and `public init?(rawValue: String)`. `Exercise.art: ArtChoice` (computed, backed by stored `artRaw: String?`).

Raw encoding: `"unmatched"`, `"none"`, `"library:<slug>"`. Store as `String?` and read through the computed property, matching the `phaseStorage`/`phase` pattern already used for migrating stores.

- [ ] **Step 1: Write the failing test**

```swift
func test_rawValueRoundTripsAllCases() {
    for c in [ArtChoice.unmatched, .none, .library(slug: "bird-dog")] {
        XCTAssertEqual(ArtChoice(rawValue: c.rawValue), c)
    }
}

func test_unknownRawValueIsNil() {
    XCTAssertNil(ArtChoice(rawValue: "wat"))
    XCTAssertNil(ArtChoice(rawValue: "library:"))
}

func test_exerciseDefaultsToUnmatched() {
    let e = Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both)
    XCTAssertEqual(e.art, .unmatched)
}

func test_exerciseArtSurvivesAssignment() {
    let e = Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30, side: .both)
    e.art = .library(slug: "bird-dog")
    XCTAssertEqual(e.art, .library(slug: "bird-dog"))
    e.art = .none
    XCTAssertEqual(e.art, .none)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:DataKitTests/ArtChoiceTests`
Expected: FAIL — `ArtChoice` and `Exercise.art` do not exist.

- [ ] **Step 3: Implement `ArtChoice` and add `art` to `Exercise`**

Add `art: ArtChoice = .unmatched` as the last parameter of `Exercise.init`, after `lineageID`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:DataKitTests`
Expected: PASS, including existing model and repository tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/DataKit/Models/ArtChoice.swift Packages/PTAppCore/Sources/DataKit/Models/Exercise.swift Packages/PTAppCore/Tests/DataKitTests/ArtChoiceTests.swift
git commit -m "feat(data): add ArtChoice to Exercise"
```

---

### Task 2: Carry the art choice through both `ParsedRoutine` paths

**Files:**
- Modify: `Packages/PTAppCore/Sources/ParsingKit/ParsedRoutine.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/ParsedRoutine+Editing.swift`
- Test: `Packages/PTAppCore/Tests/ParsingKitTests/ParsedRoutineTests.swift`

**Interfaces:**
- Consumes: `ArtChoice` (Task 1).
- Produces: `ParsedRoutine.ParsedExercise.art: ArtChoice` defaulting to `.unmatched`, carried by all three conversions — `toRoutine()`, `ParsedExercise.init(exercise:)`, and `apply(to:)`.

This is what makes the picture editable after Save without a second write path, and it is the one place a silent data loss can hide: `apply(to:)` mutates existing exercises field by field, so an `art` it forgets to copy is an `art` the editor erases.

- [ ] **Step 1: Write the failing test**

```swift
func test_toRoutineCarriesArtChoice() {
    let parsed = ParsedRoutine(name: "R", exercises: [
        .init(name: "Bird Dog", reps: 10, sets: 3, durationSec: nil, restSec: 30,
              side: "both", notes: "", art: .library(slug: "bird-dog")),
        .init(name: "Mystery", reps: 10, sets: 3, durationSec: nil, restSec: 30,
              side: "both", notes: "", art: .none),
    ])
    XCTAssertEqual(parsed.toRoutine().orderedExercises.map(\.art),
                   [.library(slug: "bird-dog"), .none])
}

func test_draftingASavedRoutineKeepsArt() {
    let routine = Routine(name: "R", exercises: [
        Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30,
                 side: .both, order: 0, art: .library(slug: "bird-dog")),
    ])
    XCTAssertEqual(ParsedRoutine(routine: routine).exercises.first?.art,
                   .library(slug: "bird-dog"))
}

func test_applyPreservesArtOnUntouchedExercises() {
    // Review Focus 5: editing the name must not erase the picture.
    let routine = Routine(name: "R", exercises: [
        Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30,
                 side: .both, order: 0, art: .library(slug: "bird-dog")),
    ])
    var draft = ParsedRoutine(routine: routine)
    draft.exercises[0].name = "Bird Dog (right)"
    draft.apply(to: routine)
    XCTAssertEqual(routine.orderedExercises.first?.art, .library(slug: "bird-dog"))
    XCTAssertEqual(routine.orderedExercises.first?.name, "Bird Dog (right)")
}

func test_applyWritesAChangedArtChoice() {
    let routine = Routine(name: "R", exercises: [
        Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30,
                 side: .both, order: 0, art: .library(slug: "bird-dog")),
    ])
    var draft = ParsedRoutine(routine: routine)
    draft.exercises[0].art = .none
    draft.apply(to: routine)
    XCTAssertEqual(routine.orderedExercises.first?.art, .none)
}

func test_decodingWithoutArtDefaultsToUnmatched() throws {
    let json = #"{"name":"R","exercises":[{"name":"X","sets":3,"restSec":30,"side":"both","notes":""}]}"#
    let parsed = try JSONDecoder().decode(ParsedRoutine.self, from: Data(json.utf8))
    XCTAssertEqual(parsed.exercises[0].art, .unmatched)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:ParsingKitTests/ParsedRoutineTests`
Expected: FAIL — no `art` parameter.

- [ ] **Step 3: Add `art` to `ParsedExercise` and carry it through all three conversions**

Add `art` as the last `init` parameter with default `.unmatched`, add it to `CodingKeys`, and decode it with the same tolerant fallback the custom `init(from:)` already uses for `id`. Then update `toRoutine()`, `ParsedExercise.init(exercise:)`, and both branches of `apply(to:)` — the existing-exercise mutation and the new-`Exercise` construction.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:ParsingKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/ParsingKit Packages/PTAppCore/Tests/ParsingKitTests/ParsedRoutineTests.swift
git commit -m "feat(parsing): carry ArtChoice through import and in-place editing"
```

---

### Task 3: `MediaKit` target and the bundled catalogue

**Files:**
- Create: `Packages/PTAppCore/Sources/MediaKit/CatalogEntry.swift`
- Create: `Packages/PTAppCore/Sources/MediaKit/ExerciseCatalog.swift`
- Create: `Packages/PTAppCore/Sources/MediaKit/Resources/catalog.json`
- Create: `Packages/PTAppCore/Sources/MediaKit/Resources/generate-catalog.sh`
- Modify: `Packages/PTAppCore/Package.swift`
- Test: `Packages/PTAppCore/Tests/MediaKitTests/ExerciseCatalogTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct CatalogEntry: Codable, Sendable, Equatable, Identifiable { public let slug: String; public let name: String; public let equipment: String; public let primaryMuscle: String; public let secondaryMuscles: [String]; public let isStretch: Bool; public var id: String { slug } }`
  - `public struct ExerciseCatalog: Sendable { public static let bundled: ExerciseCatalog; public let entries: [CatalogEntry]; public func entry(slug: String) -> CatalogEntry? }`

Add a `MediaKit` library target with `resources: [.process("Resources")]`, depending on `DataKit`, plus a `MediaKitTests` test target.

`generate-catalog.sh` fetches `https://cdn.jsdelivr.net/npm/@bryllim/workout-guide@1.0.0/manifest.json`, keeps entries whose `equipment` is one of `Bodyweight`, `Resistance Band`, `Wall`, `Towel`, `Doorway`, `Chair`, `Box`, `Stability Ball`, drops the per-frame and attribution fields, and writes `catalog.json`. Committed output, run by hand when upstream changes.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests`
Expected: FAIL — target does not exist.

- [ ] **Step 3: Add the target, write the generator, commit its output, implement `ExerciseCatalog`**

`bundled` decodes `catalog.json` from `Bundle.module`. It is a `static let`, so decode failure must not trap — fall back to empty `entries` and log via `os.Logger(subsystem: "PTAppCore", category: "media")`, matching how `ParsingKit` logs.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Package.swift Packages/PTAppCore/Sources/MediaKit Packages/PTAppCore/Tests/MediaKitTests
git commit -m "feat(media): add MediaKit with bundled exercise catalogue"
```

---

### Task 4: Stage-1 candidate scoring

**Files:**
- Create: `Packages/PTAppCore/Sources/MediaKit/CandidateScorer.swift`
- Test: `Packages/PTAppCore/Tests/MediaKitTests/CandidateScorerTests.swift`

**Interfaces:**
- Consumes: `CatalogEntry`, `ExerciseCatalog` (Task 3).
- Produces: `public struct ScoredCandidate: Sendable, Equatable { public let entry: CatalogEntry; public let score: Double }` and `public struct CandidateScorer: Sendable { public init(catalog: ExerciseCatalog = .bundled); public func candidates(for name: String, limit: Int = 8) -> [ScoredCandidate] }`.

Scores run `0...1`, descending, at most `limit`. Normalisation is the implementer's design; the tests pin the behaviour that matters.

- [ ] **Step 1: Write the failing test**

```swift
func test_exactNameScoresTop() {
    let s = CandidateScorer()
    XCTAssertEqual(s.candidates(for: "Bird Dog").first?.entry.slug, "bird-dog")
    XCTAssertEqual(s.candidates(for: "clamshell").first?.entry.slug, "clamshell")
}

func test_handoutPhrasingFindsTheRightFamily() {
    let s = CandidateScorer()
    // Real handout wording. The right answer need only be in the shortlist —
    // stage 2 picks. See spec: "rank the few plausible ones".
    let cases: [(String, String)] = [
        ("Quadruped Opposite Arm/Leg Raise", "bird-dog"),
        ("Side-Lying Hip Abduction - Right", "side-lying-hip-abduction"),
        ("Supine Glute Bridge x10", "glute-bridge"),
    ]
    for (input, expected) in cases {
        let slugs = s.candidates(for: input).map(\.entry.slug)
        XCTAssertTrue(slugs.contains(expected), "\(input) → \(slugs)")
    }
}

func test_garbageInputYieldsNoCandidates() {
    let s = CandidateScorer()
    for junk in ["", "   ", "Page 2 of 3", "11/04/2026", "Riverside Physical Therapy"] {
        XCTAssertTrue(s.candidates(for: junk).isEmpty, "\(junk)")
    }
}

func test_respectsLimit() {
    XCTAssertLessThanOrEqual(CandidateScorer().candidates(for: "squat", limit: 3).count, 3)
}

func test_scoresAreDescendingAndNormalised() {
    let c = CandidateScorer().candidates(for: "bridge")
    XCTAssertEqual(c, c.sorted { $0.score > $1.score })
    XCTAssertTrue(c.allSatisfy { (0...1).contains($0.score) })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests/CandidateScorerTests`
Expected: FAIL — `CandidateScorer` not defined.

- [ ] **Step 3: Implement `CandidateScorer`**

`candidates(for:limit:)` returns `[]` when the normalised name has no token overlap with any entry — that is what makes `test_garbageInputYieldsNoCandidates` pass and is the first half of the spec's confidence floor.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/MediaKit/CandidateScorer.swift Packages/PTAppCore/Tests/MediaKitTests/CandidateScorerTests.swift
git commit -m "feat(media): add stage-1 candidate scoring"
```

---

### Task 5: The matcher, with the on-device ranking stage

**Files:**
- Create: `Packages/PTAppCore/Sources/MediaKit/ExerciseMatcher.swift`
- Create: `Packages/PTAppCore/Sources/MediaKit/FoundationModelsRanker.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/FoundationModelsExtractor.swift` (its comment claims it is the only file importing FoundationModels)
- Test: `Packages/PTAppCore/Tests/MediaKitTests/ExerciseMatcherTests.swift`

**Interfaces:**
- Consumes: `CandidateScorer`, `ScoredCandidate` (Task 4); `ArtChoice` (Task 1).
- Produces:
  - `public protocol CandidateRanker: Sendable { var isAvailable: Bool { get }; func rank(name: String, notes: String, candidates: [ScoredCandidate]) async throws -> [String] }` — slugs best-first, empty for "none of these".
  - `public struct FoundationModelsRanker: CandidateRanker`
  - `public struct StubRanker: CandidateRanker` — `init(slugs: [String], isAvailable: Bool = true)`.
  - `public struct ThrowingRanker: CandidateRanker` — `rank` always throws, `isAvailable` is `true`. Used here and in Task 8.
  - `public struct MatchResult: Sendable, Equatable { public let choice: ArtChoice; public let alternatives: [String] }`
  - `public struct ExerciseMatcher: Sendable { public init(scorer: CandidateScorer = .init(), ranker: CandidateRanker = FoundationModelsRanker(), floor: Double = 0.45); public func match(name: String, notes: String) async -> MatchResult }`

`match` never throws: a ranker failure falls back to stage 1, mirroring how `RoutineParser.extract` falls through its extractor chain.

- [ ] **Step 1: Write the failing test**

```swift
func test_rankerChoiceWins() async {
    let m = ExerciseMatcher(ranker: StubRanker(slugs: ["clamshell", "fire-hydrant"]))
    let r = await m.match(name: "Side-Lying Clam", notes: "")
    XCTAssertEqual(r.choice, .library(slug: "clamshell"))
    XCTAssertEqual(r.alternatives, ["fire-hydrant"])
}

func test_rankerSayingNoneYieldsNoPicture() async {
    let m = ExerciseMatcher(ranker: StubRanker(slugs: []))
    let r = await m.match(name: "Slant Board Gastrocnemius Stretch", notes: "")
    XCTAssertEqual(r.choice, .none)
}

func test_degradesToStageOneWhenModelUnavailable() async {
    let m = ExerciseMatcher(ranker: StubRanker(slugs: [], isAvailable: false))
    let r = await m.match(name: "Bird Dog", notes: "")
    XCTAssertEqual(r.choice, .library(slug: "bird-dog"))
}

func test_floorAppliesOnStageOneOnlyPath() async {
    // Review Focus 2: model unavailable must not ship the least-bad slug.
    let m = ExerciseMatcher(ranker: StubRanker(slugs: [], isAvailable: false), floor: 0.99)
    let r = await m.match(name: "Slant Board Gastrocnemius Stretch", notes: "")
    XCTAssertEqual(r.choice, .none)
}

func test_noCandidatesSkipsRankerEntirely() async {
    let m = ExerciseMatcher(ranker: StubRanker(slugs: ["bird-dog"]))
    let r = await m.match(name: "Page 2 of 3", notes: "")
    XCTAssertEqual(r.choice, .none)
    XCTAssertTrue(r.alternatives.isEmpty)
}

func test_rankerThrowingFallsBackToStageOne() async {
    let m = ExerciseMatcher(ranker: ThrowingRanker())
    let r = await m.match(name: "Bird Dog", notes: "")
    XCTAssertEqual(r.choice, .library(slug: "bird-dog"))
}

func test_slugNotInShortlistIsDiscarded() async {
    let m = ExerciseMatcher(ranker: StubRanker(slugs: ["totally-made-up"]))
    let r = await m.match(name: "Bird Dog", notes: "")
    XCTAssertNotEqual(r.choice, .library(slug: "totally-made-up"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests/ExerciseMatcherTests`
Expected: FAIL — `ExerciseMatcher` not defined.

- [ ] **Step 3: Implement `ExerciseMatcher`, `FoundationModelsRanker`, `StubRanker`, `ThrowingRanker`**

`FoundationModelsRanker` follows `FoundationModelsExtractor`: `isAvailable` checks `SystemLanguageModel.default.availability`; `rank` uses a `@Generable` type whose slug field is `@Guide`-constrained to the shortlist, with an explicit instruction that returning nothing is correct when no candidate is the same movement. Build the `LanguageModelSession` per call.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/MediaKit Packages/PTAppCore/Sources/ParsingKit/FoundationModelsExtractor.swift Packages/PTAppCore/Tests/MediaKitTests/ExerciseMatcherTests.swift
git commit -m "feat(media): add two-stage exercise matcher"
```

---

### Task 6: The art store — download, cache, resolve

**Files:**
- Create: `Packages/PTAppCore/Sources/MediaKit/ArtStore.swift`
- Create: `Packages/PTAppCore/Sources/MediaKit/FrameDownloader.swift`
- Create: `Packages/PTAppCore/Tests/MediaKitTests/TempDirectory.swift`
- Test: `Packages/PTAppCore/Tests/MediaKitTests/ArtStoreTests.swift`

**Interfaces:**
- Consumes: `ExerciseCatalog` (Task 3).
- Produces:
  - `public protocol FrameDownloading: Sendable { func data(slug: String, frame: Int) async throws -> Data }`
  - `public struct CDNFrameDownloader: FrameDownloading` — builds the base URL from Global Constraints.
  - `public actor StubFrameDownloader: FrameDownloading` — `init(data: Data = Data([0x89, 0x50, 0x4E, 0x47]), failing: Bool = false)`, exposing `public var callCount: Int`.
  - `public actor ArtStore { public init(downloader: FrameDownloading = CDNFrameDownloader(), directory: URL? = nil); public func frame(slug: String, frame: Int) async -> Data?; public func prefetch(slugs: [String]) async }`

`frame` returns `nil` rather than throwing — a missing picture is a normal state, not an error. `directory: nil` means Application Support; tests pass a temporary directory.

`TempDirectory.swift` holds an `XCTestCase` extension `tempDir() -> URL` returning a fresh directory under `FileManager.default.temporaryDirectory`, removed in `tearDown`. Task 7 needs the same helper from `UITests`; duplicate it there rather than exporting test code across targets.

- [ ] **Step 1: Write the failing test**

```swift
func test_downloadsOnceThenServesFromCache() async {
    let dl = StubFrameDownloader()
    let store = ArtStore(downloader: dl, directory: tempDir())
    let a = await store.frame(slug: "bird-dog", frame: 1)
    let b = await store.frame(slug: "bird-dog", frame: 1)
    XCTAssertNotNil(a)
    XCTAssertEqual(a, b)
    let calls = await dl.callCount
    XCTAssertEqual(calls, 1)
}

func test_cacheSurvivesANewStoreOverTheSameDirectory() async {
    let dir = tempDir()
    let dl = StubFrameDownloader()
    _ = await ArtStore(downloader: dl, directory: dir).frame(slug: "clamshell", frame: 1)
    _ = await ArtStore(downloader: dl, directory: dir).frame(slug: "clamshell", frame: 1)
    let calls = await dl.callCount
    XCTAssertEqual(calls, 1)
}

func test_offlineReturnsNilAndRetriesLater() async {
    // Review Focus 1: first launch with no network.
    let dir = tempDir()
    XCTAssertNil(await ArtStore(downloader: StubFrameDownloader(failing: true), directory: dir)
        .frame(slug: "bird-dog", frame: 1))
    // A later launch with network succeeds — the failure was not cached.
    XCTAssertNotNil(await ArtStore(downloader: StubFrameDownloader(), directory: dir)
        .frame(slug: "bird-dog", frame: 1))
}

func test_unknownSlugReturnsNilWithoutDownloading() async {
    // Review Focus 3: a slug no longer in the catalogue.
    let dl = StubFrameDownloader()
    let store = ArtStore(downloader: dl, directory: tempDir())
    XCTAssertNil(await store.frame(slug: "bench-press", frame: 1))
    let calls = await dl.callCount
    XCTAssertEqual(calls, 0)
}

func test_concurrentRequestsForTheSameFrameDownloadOnce() async {
    let dl = StubFrameDownloader()
    let store = ArtStore(downloader: dl, directory: tempDir())
    await withTaskGroup(of: Void.self) { g in
        for _ in 0..<8 { g.addTask { _ = await store.frame(slug: "dead-bug", frame: 1) } }
    }
    let calls = await dl.callCount
    XCTAssertEqual(calls, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests/ArtStoreTests`
Expected: FAIL — `ArtStore` not defined.

- [ ] **Step 3: Implement `ArtStore`, `CDNFrameDownloader`, `StubFrameDownloader`, `TempDirectory`**

`ArtStore` validates the slug against `ExerciseCatalog.bundled` before any network call. In-flight requests are deduplicated by holding the `Task` for each `slug/frame` key so concurrent callers await the same one. Failures are not written to disk.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:MediaKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/MediaKit Packages/PTAppCore/Tests/MediaKitTests
git commit -m "feat(media): add downloading, caching art store"
```

---

### Task 7: `ExerciseFigure` view

**Files:**
- Create: `Packages/PTAppCore/Sources/UI/Media/ExerciseFigure.swift`
- Create: `Packages/PTAppCore/Tests/UITests/TempDirectory.swift`
- Modify: `Packages/PTAppCore/Package.swift` (UI depends on MediaKit)
- Test: `Packages/PTAppCore/Tests/UITests/ExerciseFigureTests.swift`

**Interfaces:**
- Consumes: `ArtStore` (Task 6), `ArtChoice` (Task 1).
- Produces: `public struct ExerciseFigure: View { public init(art: ArtChoice, frame: Int = 1, store: ArtStore) }` and `public extension EnvironmentValues { var artStore: ArtStore }` with a default instance.

Renders the PNG as a template image tinted `AppColor.ink`, `.aspectRatio(1, contentMode: .fit)`. For `.unmatched`, `.none`, or art that has not arrived, renders an empty space of the same size — no placeholder glyph, no spinner. Always `.accessibilityHidden(true)`.

- [ ] **Step 1: Write the failing test**

```swift
func test_noPictureStatesRenderNothingVisible() throws {
    let store = ArtStore(downloader: StubFrameDownloader(failing: true), directory: tempDir())
    for art in [ArtChoice.unmatched, .none, .library(slug: "bench-press")] {
        let v = ExerciseFigure(art: art, store: store)
        XCTAssertThrowsError(try v.inspect().find(ViewType.Image.self), "\(art)")
    }
}

func test_figureIsHiddenFromVoiceOver() throws {
    let v = ExerciseFigure(art: .library(slug: "bird-dog"),
                           store: ArtStore(downloader: StubFrameDownloader(), directory: tempDir()))
    XCTAssertTrue(try v.inspect().accessibilityHidden())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests/ExerciseFigureTests`
Expected: FAIL — `ExerciseFigure` not defined.

- [ ] **Step 3: Implement `ExerciseFigure`**

Load through the store in a `.task`, keyed on slug and frame so a change reloads. Hold the loaded image in `@State`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Package.swift Packages/PTAppCore/Sources/UI/Media Packages/PTAppCore/Tests/UITests
git commit -m "feat(ui): add ExerciseFigure"
```

---

### Task 8: Match during import

**Files:**
- Modify: `Packages/PTAppCore/Sources/UI/Setup/SetupViewModel.swift`
- Test: `Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift`

**Interfaces:**
- Consumes: `ExerciseMatcher`, `MatchResult`, `StubRanker`, `ThrowingRanker` (Task 5).
- Produces: a `matcher: ExerciseMatcher = .init()` parameter on `SetupViewModel.init`.

After a successful parse and before the editing phase begins, match every exercise concurrently in a `withTaskGroup` and write each `ArtChoice` onto the draft. Matching must not fail the import: if it throws, exercises keep `.unmatched` and the editor still appears.

Read the current `SetupViewModel` before writing — it has grown beyond photo parsing (files, PDFs, brain dump) and the matching hook belongs on every path that produces a draft.

- [ ] **Step 1: Write the failing test**

```swift
func test_parseAssignsArtToDraftExercises() async {
    let vm = SetupViewModel(routineRepo: repo,
                            parser: RoutineParser(extractors: [StubExtractor(result: twoExerciseRoutine)]),
                            matcher: ExerciseMatcher(ranker: StubRanker(slugs: ["bird-dog"])))
    await vm.parse(UIImage())
    XCTAssertEqual(vm.draft.exercises.first?.art, .library(slug: "bird-dog"))
}

func test_matchingFailureStillReachesTheEditor() async {
    let vm = SetupViewModel(routineRepo: repo,
                            parser: RoutineParser(extractors: [StubExtractor(result: twoExerciseRoutine)]),
                            matcher: ExerciseMatcher(ranker: ThrowingRanker()))
    await vm.parse(UIImage())
    XCTAssertNotNil(vm.editorVM)
}

func test_manualStartLeavesExercisesUnmatched() {
    let vm = SetupViewModel(routineRepo: repo)
    vm.startManual()
    XCTAssertTrue(vm.draft.exercises.allSatisfy { $0.art == .unmatched })
}
```

Adapt the parser and phase assertions to whatever `SetupViewModel` actually exposes now.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests/SetupViewModelTests`
Expected: FAIL — no `matcher` parameter.

- [ ] **Step 3: Add matching to `SetupViewModel`**

Build `editorVM` after matching, so the editor sees the assigned art.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Setup/SetupViewModel.swift Packages/PTAppCore/Tests/UITests/SetupViewModelTests.swift
git commit -m "feat(setup): match exercises to library art during import"
```

---

### Task 9: Figures in Today's list and the session screen

**Files:**
- Modify: `Packages/PTAppCore/Sources/UI/Home/HomeViewModel.swift`
- Modify: `Packages/PTAppCore/Sources/UI/Home/HomeView.swift` (`ExerciseRowView`)
- Modify: `Packages/PTAppCore/Sources/UI/Session/SessionViewModel.swift`
- Modify: `Packages/PTAppCore/Sources/UI/Session/SessionView.swift`
- Test: `Packages/PTAppCore/Tests/UITests/HomeViewModelTests.swift`, `Packages/PTAppCore/Tests/UITests/SessionViewModelTests.swift`

**Interfaces:**
- Consumes: `ExerciseFigure` (Task 7), `ArtChoice` (Task 1).
- Produces: `HomeViewModel.ExerciseRow.art: ArtChoice`; `SessionViewModel.currentArt: ArtChoice`.

`ExerciseRowView` gains a leading 44×44 figure. The session figure sits above the title block, capped so it yields space before the timer does — at accessibility text sizes the number keeps its size and the figure shrinks or disappears.

- [ ] **Step 1: Write the failing test**

```swift
// HomeViewModelTests
func test_rowsCarryArtChoice() async {
    try routineRepo.save(Routine(name: "R", exercises: [
        Exercise(name: "Bird Dog", target: .repsSets(reps: 10, sets: 3), restSeconds: 30,
                 side: .both, order: 0, art: .library(slug: "bird-dog")),
    ]))
    let vm = HomeViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
    await vm.refresh()
    XCTAssertEqual(vm.rows.first?.art, .library(slug: "bird-dog"))
}

// SessionViewModelTests
func test_currentArtTracksTheCurrentExercise() {
    let vm = SessionViewModel(routine: twoExerciseRoutineWithArt, sessionRepo: sessionRepo)
    XCTAssertEqual(vm.currentArt, .library(slug: "bird-dog"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests`
Expected: FAIL — no `art` on `ExerciseRow`, no `currentArt`.

- [ ] **Step 3: Add `art` to `ExerciseRow` and `currentArt` to `SessionViewModel`, then place the figures**

`ExerciseRowView`'s existing `.accessibilityElement(children: .combine)` must keep announcing number, name and prescription only — the figure is already hidden by Task 7.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Home Packages/PTAppCore/Sources/UI/Session Packages/PTAppCore/Tests/UITests
git commit -m "feat(ui): show exercise figures in Today and session"
```

---

### Task 10: The picture control in the exercise editor

**Files:**
- Create: `Packages/PTAppCore/Sources/UI/Media/ArtPickerView.swift`
- Modify: `Packages/PTAppCore/Sources/UI/RoutineEditor/ExerciseEditorView.swift`
- Modify: `Packages/PTAppCore/Sources/UI/RoutineEditor/RoutineEditorView.swift`
- Test: `Packages/PTAppCore/Tests/UITests/ArtPickerViewTests.swift`

**Interfaces:**
- Consumes: `ExerciseFigure` (Task 7), `ExerciseMatcher`, `CatalogEntry` (Tasks 3, 5).
- Produces: `public struct ArtPickerView: View { public init(art: Binding<ArtChoice>, exerciseName: String, matcher: ExerciseMatcher = .init()) }`

**This one control covers both of the spec's editing moments** — import review and after-save correction — because `EditRoutineView` and `SetupView` both reach `ExerciseEditorView` through `RoutineEditorView`. Nothing else is needed to make a picture correctable after Save.

`ArtPickerView` lists suggestions (the matcher's choice followed by its alternatives, each mapped through `ExerciseCatalog.bundled.entry(slug:)` and dropped if unresolvable) plus a "No picture" row, each with its own small figure. `ExerciseEditorView` gains a "Picture" section showing the current figure and a `NavigationLink` to the picker. `RoutineEditorView`'s rows gain a leading figure so suggestions are visible while reviewing.

- [ ] **Step 1: Write the failing test**

```swift
func test_pickerOffersSuggestionsAndNoPicture() throws {
    var art = ArtChoice.unmatched
    let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }),
                          exerciseName: "Bird Dog",
                          matcher: ExerciseMatcher(ranker: StubRanker(slugs: ["bird-dog", "dead-bug"])))
    XCTAssertNoThrow(try v.inspect().find(text: "No picture"))
}

func test_choosingNoPictureSetsNone() throws {
    var art = ArtChoice.library(slug: "bird-dog")
    let v = ArtPickerView(art: Binding(get: { art }, set: { art = $0 }), exerciseName: "Bird Dog")
    try v.inspect().find(button: "No picture").tap()
    XCTAssertEqual(art, .none)
}

func test_editorShowsThePictureSection() throws {
    var ex = ParsedRoutine.ParsedExercise(name: "Bird Dog", reps: 10, sets: 3, durationSec: nil,
                                          restSec: 30, side: "both", notes: "")
    let v = ExerciseEditorView(exercise: Binding(get: { ex }, set: { ex = $0 }))
    XCTAssertNoThrow(try v.inspect().find(text: "Picture"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests/ArtPickerViewTests`
Expected: FAIL — `ArtPickerView` not defined.

- [ ] **Step 3: Implement `ArtPickerView` and wire it into the editor**

Suggestions load in a `.task`; the picker is usable before they arrive, since "No picture" is always available.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Media/ArtPickerView.swift Packages/PTAppCore/Sources/UI/RoutineEditor Packages/PTAppCore/Tests/UITests/ArtPickerViewTests.swift
git commit -m "feat(ui): choose an exercise picture, in setup and after save"
```

---

### Task 11: The figure and frame scrub on the exercise screen

**Files:**
- Modify: `Packages/PTAppCore/Sources/UI/Progress/ProgressViewModel.swift`
- Modify: `Packages/PTAppCore/Sources/UI/Progress/ProgressDetailViews.swift` (`ExerciseProgressView`)
- Test: `Packages/PTAppCore/Tests/UITests/ProgressViewModelTests.swift`

**Interfaces:**
- Consumes: `ExerciseFigure` (Task 7), `ArtChoice` (Task 1).
- Produces: `ProgressViewModel.ExerciseRow.art: ArtChoice`.

`ExerciseProgressView` gains a large figure above the name, a scrub across frames 1–3, and the attribution line from Global Constraints below. The scrub is the implementer's choice of gesture or segmented control; whichever it is, it must be reachable by VoiceOver and keyboard, and clamp to 1...3.

Read `ProgressViewModel` first — `ExerciseRow` is built from history, not only from the live routine, so an exercise from an earlier phase may have no matching `Exercise` row to read `art` from. In that case use `.unmatched`.

- [ ] **Step 1: Write the failing test**

```swift
func test_exerciseRowCarriesArt() {
    // Build a routine with art, refresh, and read it back off the row.
    let vm = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
    vm.refresh()
    XCTAssertEqual(vm.exercise(id: birdDogID)?.art, .library(slug: "bird-dog"))
}

func test_exerciseFromAnEarlierPhaseHasNoArt() {
    let vm = ProgressViewModel(routineRepo: routineRepo, sessionRepo: sessionRepo)
    vm.refresh()
    XCTAssertEqual(vm.exercise(id: retiredExerciseID)?.art, .unmatched)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests/ProgressViewModelTests`
Expected: FAIL — no `art` on `ExerciseRow`.

- [ ] **Step 3: Add `art` to `ExerciseRow` and place the figure, scrub and attribution**

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command, then `xcodegen generate --spec App/project.yml --project App` and build the app target.
Expected: PASS, app builds.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Progress Packages/PTAppCore/Tests/UITests/ProgressViewModelTests.swift
git commit -m "feat(ui): show the exercise figure and frame scrub on the exercise screen"
```

---

### Task 12: Carry the sheet's how-to text

**Files:**
- Create: `Packages/PTAppCore/Sources/DataKit/Models/HowToSection.swift`
- Modify: `Packages/PTAppCore/Sources/DataKit/Models/Exercise.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/ParsedRoutine.swift`, `ParsedRoutine+Editing.swift`
- Modify: `Packages/PTAppCore/Sources/ParsingKit/FoundationModelsExtractor.swift`
- Modify: `Packages/PTAppCore/Sources/UI/Progress/ProgressDetailViews.swift`
- Test: `Packages/PTAppCore/Tests/DataKitTests/HowToSectionTests.swift`, `Packages/PTAppCore/Tests/ParsingKitTests/ParsedRoutineTests.swift`

**Interfaces:**
- Consumes: `ExerciseProgressView` (Task 11).
- Produces: `public struct HowToSection: Codable, Sendable, Equatable, Identifiable { public let id: UUID; public let heading: String; public let body: String }`; `Exercise.sheetHowTo: [HowToSection]` (computed over stored `sheetHowToData: Data?`, mirroring `targetData`); `ParsedExercise.sheetHowTo: [HowToSection]`, carried by all three conversions as in Task 2.

The field name carries the provenance: everything in `sheetHowTo` came off the handout. When generation is added later it gets its own field, and the `Exercise.notes` path to the session screen stays closed to it.

The extractor's `@Generable` exercise gains a sections array `@Guide`-described as the handout's own labelled instruction blocks, headings copied verbatim, empty when the sheet has none. Do not require the labels `Setup`/`Movement`/`Tip`. Note the app already imports PDFs and text (`RoutineDocument`), so this prose often arrives as real text rather than OCR.

- [ ] **Step 1: Write the failing test**

```swift
func test_sectionsRoundTripThroughTheModel() {
    let e = Exercise(name: "X", target: .repsSets(reps: 1, sets: 1), restSeconds: 0, side: .both)
    e.sheetHowTo = [HowToSection(heading: "Setup", body: "Begin standing behind a slant board.")]
    XCTAssertEqual(e.sheetHowTo.map(\.heading), ["Setup"])
}

func test_allThreeConversionsCarrySheetHowTo() {
    let section = HowToSection(heading: "Tip", body: "Keep your heels down.")
    let parsed = ParsedRoutine(name: "R", exercises: [
        .init(name: "X", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both",
              notes: "", sheetHowTo: [section]),
    ])
    let routine = parsed.toRoutine()
    XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [section])
    XCTAssertEqual(ParsedRoutine(routine: routine).exercises.first?.sheetHowTo, [section])
    var draft = ParsedRoutine(routine: routine)
    draft.exercises[0].name = "Y"
    draft.apply(to: routine)
    XCTAssertEqual(routine.orderedExercises.first?.sheetHowTo, [section])
}

func test_sheetHowToDoesNotLeakIntoNotes() {
    // Spec anti-goal: Exercise.notes renders beside the running timer.
    let parsed = ParsedRoutine(name: "R", exercises: [
        .init(name: "X", reps: 1, sets: 1, durationSec: nil, restSec: 0, side: "both", notes: "",
              sheetHowTo: [HowToSection(heading: "Tip", body: "Keep your heels down.")]),
    ])
    XCTAssertEqual(parsed.toRoutine().orderedExercises.first?.notes, "")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:DataKitTests`
Expected: FAIL — `HowToSection` not defined.

- [ ] **Step 3: Implement `HowToSection`, thread it through model, DTO, both editing conversions and the extractor, and render it on the exercise screen**

Sections render under the figure in sheet order, heading then body.

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/DataKit Packages/PTAppCore/Sources/ParsingKit Packages/PTAppCore/Sources/UI/Progress Packages/PTAppCore/Tests
git commit -m "feat: carry the sheet's how-to text onto the exercise screen"
```

---

### Task 13: Attribution in Settings

**Files:**
- Modify: `Packages/PTAppCore/Sources/UI/Settings/SettingsView.swift`
- Test: `Packages/PTAppCore/Tests/UITests/SettingsSnapshotTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

A "Credits" section carrying the attribution string from Global Constraints verbatim, with a link to `https://creativecommons.org/licenses/by-sa/4.0/`.

- [ ] **Step 1: Write the failing test**

```swift
func test_settingsShowsIllustrationCredit() throws {
    let view = SettingsView(viewModel: SettingsViewModel(), onReplaceRoutine: {}, onDone: {})
    XCTAssertNoThrow(try view.inspect().find(
        text: "Exercise illustrations by Bryl Lim, licensed CC BY-SA 4.0. Derived from Everkinetic."))
}
```

Check `SettingsView`'s current initialiser before writing — it may have grown parameters.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:PTAppCore-Package:UITests/SettingsSnapshotTests`
Expected: FAIL — text not present.

- [ ] **Step 3: Add the Credits section**

- [ ] **Step 4: Run tests to verify they pass**

Run the full test command, then regenerate and build the app target.
Expected: PASS, app builds.

- [ ] **Step 5: Commit**

```bash
git add Packages/PTAppCore/Sources/UI/Settings Packages/PTAppCore/Tests/UITests/SettingsSnapshotTests.swift
git commit -m "feat(settings): credit the exercise illustrations"
```
