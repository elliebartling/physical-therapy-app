# PT App — Design (v1)

## Context

Greenfield iOS app for someone following a PT-prescribed physical therapy routine on their own. The user uploads/configures the routine themselves (no therapist account, no clinic sync) and the app's job is to make the daily routine as low-friction as possible — guided, hands-free, minimal taps. The brief explicitly calls out usability and low friction as the design north star.

The data model and module boundaries are designed so several capabilities the user wants eventually — PT-export, exercise media, gamification badges, multiple parallel routines — can be added as additive features later without a rewrite. None of those features are built in v1.

Target stack: iOS 26+, native SwiftUI, SwiftData + CloudKit sync, Apple Foundation Models for on-device parsing.

## Product shape (v1)

Three jobs the app does:

1. **Onboard the routine once.** Photo of the PT handout → on-device Foundation Models extraction → editable parsed list → save. Manual entry is always available as fallback or for tweaks.
2. **Run a guided session daily.** Fullscreen guided experience with timer/rep counter, audio + haptic cues on phase changes, auto-advance through sets and exercises. Designed to be usable phone-down on a mat.
3. **Show progress.** Streak number + monthly calendar heatmap on Home. No per-session journal, pain scale, or charts in v1.

Reminders are optional (off by default). One daily local notification at a user-chosen time when enabled.

## Architecture

Vertical slices over a shared data layer. Modules:

```
PTApp (app shell, navigation)
├── DataKit       — SwiftData models + CloudKit sync + repositories
├── ParsingKit    — Image → ParsedRoutine (VisionKit OCR + Foundation Models)
├── SessionKit    — Guided-session state machine + audio/haptic cues
├── HistoryKit    — Streak math + heatmap matrix over SessionRecords
└── UI            — SwiftUI screens, each backed by an @Observable view model
```

- **DataKit** is the only thing that touches SwiftData. Other modules go through repositories (`RoutineRepository`, `SessionRepository`) so future migrations stay contained.
- **ParsingKit** is a pure `Image -> ParsedRoutine` function. No persistence, no side effects. Easy to swap to a cloud LLM later.
- **SessionKit** is a state machine that takes a `Routine` and emits phase events (`.exerciseStarted`, `.setStarted`, `.rest`, `.sideSwitch`, `.completed`). Handles AVFoundation audio, haptics, and idle-timer suppression.
- **HistoryKit** is pure computation over `SessionRecord`s. This is where future PT-export and badge engines plug in.

## Data model

```
Routine { id, name, createdAt, isActive, exercises: [Exercise] (ordered) }
Exercise {
  id, name, target: ExerciseTarget, restSeconds,
  side: Side, notes, media: [Asset]    // media slot exists, v1 UI ignores it
}
ExerciseTarget = .repsSets(reps, sets) | .timeSets(seconds, sets)
Side = .both | .left | .right | .alternating
Asset { id, kind: .image|.video, url } // schema-only in v1

SessionRecord { id, routineId, startedAt, completedAt?, exerciseRecords }
ExerciseRecord { id, exerciseId, status: .completed|.skipped|.partial, startedAt, completedAt? }
```

Routine is a first-class entity with an ID (not a singleton). v1 UI only shows the active one, but multi-routine support is a query change, not a migration. Session logs are structured per-exercise so PT-export and badge queries already have the data they need.

CloudKit sync uses SwiftData's `.private` configuration — no account UI, uses the user's Apple ID.

## Screens

1. **Home** — large streak number, monthly heatmap, single "Start" button, gear icon.
2. **Setup / new routine** — camera shutter → parse spinner → editable parsed list → save. Skip-to-manual link always visible.
3. **Routine editor** — reorderable exercise list. Swipe to delete, tap to edit, "+ Add exercise."
4. **Exercise editor** — name, segmented control for target type (Reps × Sets / Time × Sets), the two inputs the target needs, rest seconds, side picker, optional note.
5. **Guided session** — fullscreen. Current exercise name, set N of M, big timer or rep counter, audio + haptic cues at phase changes. Three controls: Pause, Skip, Repeat set. Tap-anywhere to pause for one-handed use.
6. **Session complete** — streak update animation, back to home.
7. **Settings** — daily reminder toggle + time picker, iCloud sync indicator, "Replace routine" (re-runs setup).

## Edge cases

- **Camera/photo permission denied** → setup falls through to manual-entry editor.
- **Low-confidence/empty parse** → editor opens pre-filled with raw OCR lines as draft exercises.
- **Session interrupted** (call, app backgrounded > 10 min) → resumable on relaunch; otherwise saved as `.partial`.
- **Empty Home state** (no routine) → "Set up your routine" CTA replaces the streak block.
- **iCloud merge conflict** on `Routine` edits → last-write-wins; `SessionRecord`s are additive (insert-only) so they merge cleanly.

## Out of scope (built later, infra ready)

- PT export / share (PDF/CSV adherence report) — new view over `HistoryKit`.
- Exercise media (user-attached photos/clips, built-in video library) — `Asset` slot already on `Exercise`.
- Achievement / badge engine — new event consumer over `SessionRecord`s.
- Multiple routines (morning/evening, progression phases) — new query in `RoutineRepository` + selector UI.

## Visual system

**Aesthetic:** High-contrast technical. Pure black / pure white, hairline rules, oversized mono numerics. References: Linear, Vercel docs, Berkeley Mono marketing.

- **Color:** `#FFFFFF`/`#0A0A0A` surfaces, `#E5E5E5`/`#222222` hairlines, accent **safety yellow `#FFD60A`** used only on the streak number, "Start" button, and session-complete moments.
- **Type:** JetBrains Mono (bundled) for numerics/titles/labels/exercise names, SF Pro for body. Tabular figures locked on for ticking numbers.
- **Layout:** 8pt grid, 24pt screen padding, hairline 0.5pt dividers, no cards or shadows.
- **Icons:** SF Symbols at `.thin` weight; filled only on active session controls.
- **Motion:** Minimal, mechanical. Cross-fade on phase text, scale-pop on rep number, paired with haptic + audio.
- **Session screen:** Timer/rep fills ~60% of screen in mono safety yellow; exercise name above, `N / M` set indicator below; three flat controls (Pause / Skip / Repeat) at the bottom; tap-anywhere-else to pause; `L`/`R` flips for `.alternating`.

## Verification

**Unit (XCTest, per-module):**
- DataKit: repository CRUD, `ExerciseTarget` codec, streak edge cases.
- ParsingKit: fixture images → expected `ParsedRoutine`. Stub Foundation Models in tests.
- SessionKit: phase machine with a synthetic clock.
- HistoryKit: fixture records → expected streak + heatmap matrix.

**Snapshot:** each top-level screen in empty/populated/error states.

**Manual on-device:** photo-setup, full session phone-down with audio + haptic, pause + lock + resume, streak/heatmap update, force-quit resume, iCloud second-device sync, reminder firing.
