# Finish v1 — Real Parsing + Device Verification (Design)

## Context

v1 is code-complete through Task 40 of the original plan (`docs/superpowers/plans/2026-06-14-pt-app.md`), but two things were deliberately deferred:

1. `FoundationModelsParser.extract` throws unconditionally — the on-device LLM was never wired up, so the photo flow has no working extractor in production.
2. Task 41 (manual on-device verification) has not been run.

This design closes both. It also fixes a gap against the original spec: on parse failure the setup flow currently shows a dead `.failed` state with an empty draft, instead of opening the editor pre-filled with drafts.

Foundation Models only runs on Apple Intelligence-capable devices and can be temporarily unavailable (model downloading, feature disabled). The fallback path is therefore a first-class branch, not an edge case. Decision: a hand-rolled heuristic line parser is the never-failing floor; the LLM is an upgrade, not a requirement.

Hardware on hand for verification: one Apple Intelligence-capable iPhone. No second device — the iCloud sync check is deferred.

## Architecture: extractor chain

`RoutineParser` tries an ordered list of extractors instead of holding exactly one.

- `RoutineExtractor` gains `var isAvailable: Bool { get }`, defaulting to `true` via a protocol extension.
- `RoutineParser.init` takes `extractors: [RoutineExtractor]`, defaulting to `[FoundationModelsExtractor(), HeuristicExtractor()]`.
- `parse(_ image:)` runs OCR once, then walks the chain: skip extractors where `isAvailable == false`; on throw, try the next. The heuristic extractor never throws, so extraction always yields a `ParsedRoutine`.
- Only OCR failure (unreadable image / no recognized text) propagates to the caller.
- `StubExtractor` remains the test double, unchanged.

Module boundaries from the original spec are preserved: ParsingKit stays a pure `Image → ParsedRoutine` function; no parsing policy leaks into UI.

## HeuristicExtractor (new)

Pure text processing over OCR lines. Never throws. Pattern families:

- **Quantities:** `3 x 10`, `3 sets of 10`, `x10`, `hold 30 sec(onds)`, `2 min` → `repsSets` / `timeSets` targets.
- **Sides:** `each side`, `left` / `right`, `per leg`, `alternate` → `Side`.
- **Rest:** `rest 30s` and variants; default 30 seconds when absent (matches the existing LLM prompt's defaults).
- **Furniture filters:** lines that look like dates, clinic names, or page numbers are dropped via cheap checks.
- **Floor:** any remaining unmatched line becomes a name-only draft exercise with default 3×10.

## FoundationModelsExtractor (rewrite of FoundationModelsParser)

One file owns the `import FoundationModels`.

- A private `@Generable` DTO mirrors `ParsedRoutine` / `ParsedExercise`, with `@Guide` descriptions per field, and maps back to the domain types. Domain models never depend on the framework.
- `isAvailable` reads `SystemLanguageModel.default.availability == .available` — covers unsupported devices, Apple Intelligence disabled, and model-still-downloading.
- The session reuses the existing instruction text as `Instructions`; the OCR lines are the prompt.
- Implementation step zero: verify the current FoundationModels API surface (session type, `@Generable`/`@Guide` macros, availability enum) against Apple's docs before writing code, per the original plan's warning that symbol names were unverified.

## SetupViewModel

Happy path unchanged. `.failed` now occurs only when OCR itself fails; its message offers manual entry. The pre-filled-editor fallback happens invisibly inside the chain, so the user experience is: photo → editable drafts, always.

## Testing

TDD per module:

- **HeuristicExtractor:** fixture-line tests — one per pattern family, plus one messy multi-exercise handout fixture.
- **Chain logic:** stub extractors covering unavailable → skip, throw → next, and all-fail ordering.
- **FoundationModelsExtractor:** one live test, manually run on-device, excluded from CI (as the original plan specified). Mapping DTO → domain is unit-tested without the model.

## Verification pass (Task 41, adapted)

After the parsing work lands, build to the physical iPhone and run:

1. Real-handout scan — now exercises the true LLM path; verify parsed drafts are editable and saving activates the routine.
2. Camera-permission denial → manual-entry fallback.
3. Full session phone-down — audio + haptic cues on every phase change.
4. Pause + lock 30s + resume in place.
5. Background >10 min mid-session → relaunch shows a `.partial` SessionRecord.
6. Streak/heatmap update after completing a session.
7. Reminder fires at the chosen time; disabling stops it.
8. **Deferred:** iCloud two-device sync — requires a second device; stays on the checklist marked deferred.

## Out of scope

PT export, exercise media, badges, multiple routines (unchanged from v1 spec). No cloud-LLM extractor — the chain makes adding one later a one-line change.
