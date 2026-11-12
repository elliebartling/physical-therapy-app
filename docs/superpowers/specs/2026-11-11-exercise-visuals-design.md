# Mend — exercise visuals

Follows `2026-11-10-swiss-glass-redesign-design.md`. This spec gives every
exercise a picture you can correct, and carries the sheet's own how-to text
through to where you need it.

## Context

Today an exercise is a name and some numbers. "Bird Dog, 3 × 10" tells you what
to do only if you already know what a bird dog is. Three moments suffer:

1. **Mid-routine.** The phone is propped a metre away, the timer is running,
   and you want to confirm the shape of the thing you're doing.
2. **Scanning the list.** You're picking the right exercise out of six names
   that all sound alike.
3. **Remembering.** "Which one was the clamshell again?"

`DataKit` already anticipated this: `Asset` (`kind: .image | .video`,
`urlString`) and `Exercise.media` exist, are registered in
`ModelContainerFactory`, and are written by nothing.

## Intent

Every exercise should carry a picture that is calm, consistent, and *correctable*.

The critical realisation, and the thing that shaped everything else: the app
does not have to identify the exercise correctly. It has to get close and let
you fix it in one tap. A "wrong" match that is visibly adjacent — *Wall Calf
Stretch* offered for *Slant Board Gastrocnemius Stretch* — is a good offer, not
a failure. That reduces the on-device model's job from "identify this exercise"
to "rank the few plausible ones", which is a far easier job to do well.

## Goals

- A still line-art figure for most exercises: in the routine list, on the
  session screen, and on the exercise screen.
- Any picture is one tap from alternatives — **at any time, not only during
  import**.
- The sheet's own setup / movement / tip text carried through and attributed to
  the sheet.
- Works offline at exercise time, on device. Nothing from a handout is ever
  uploaded.

## Non-goals

- **Generating how-to text.** Deferred (see Decisions). The parsing and
  provenance work lands now so it can be added later.
- Animation. The three frames are a manual scrub, not a loop.
- Video. `Asset.Kind.video` stays in the model, unused, for later.
- Generating artwork with an image model.
- Redrawing or tracing the sheet's own images — they are photographs.
- Any new screen or navigation. Every surface this spec needs already exists.

## Anti-goals

Things that would make this a failure even if it worked:

- **A picture you can't correct.** Silent wrongness is the one outcome worse
  than a blank.
- **Invented form cues.** Generated text that contradicts the PT's instructions
  is actively unsafe.
- **Visual noise mid-session.** The session screen is for one huge number and
  one action. A picture that competes with the timer has failed.
- **A fat app.** Mend is small and should stay small.

## Decisions

Settled in conversation; not open.

### The library is the default look

Exercise art comes from **Workout Guide** (`@bryllim/workout-guide`, 302
exercises × 3 frames, 512 × 512 transparent, monochrome), derived from
Everkinetic, licensed **CC BY-SA 4.0**, attribution to Bryl Lim.

Chosen because it is one consistent visual system that tints with the accent
colour and gets dark mode for free — not for its coverage, which is its
weakness (see Constraints).

### Stills, not loops

One frame is shown. The other two are reachable by a scrub on the exercise
screen, driven by the user's finger. Nothing animates on its own, so there is
no Reduce Motion special case.

### Matches are suggestions, and they stay editable

Import assigns a best guess and the review step shows what it guessed. Changing
it is one tap: other ranked candidates, or "no picture".

**This survives Save**, and it comes almost free. Editing a saved routine
already exists: Today's Edit menu → "Edit exercises" → `EditRoutineView`, which
drafts the live routine through `ParsedRoutine(routine:)`, edits it with the
same `RoutineEditorView` / `ExerciseEditorView` the import flow uses, and writes
it back with `apply(to:)` + `RoutineRepository.saveEdits(to:removing:)`.

So the picture rides that existing round-trip. Put `art` on `ParsedExercise` and
teach `ParsedExercise.init(exercise:)` and `apply(to:)` to carry it, and one
picture control in `ExerciseEditorView` serves **both** import review and
after-save correction. No new screen, no second write path.

There is a floor: *no photo when there really isn't one*. Below it the default
is no picture rather than the least-bad candidate — otherwise the stage-1-only
path (model unavailable) ships a confident wrong picture for every exercise the
catalogue doesn't cover. "Never matched" and "user chose none" must be
distinguishable in storage, so a later re-match pass can revisit the first
without disturbing the second. "No picture" is a legitimate resting state and
must not nag.

### The sheet's own pictures are a later phase

Handout images are *correct* but inconsistent and often unattractive — the
reference sheet (MedBridge-style) uses photographs of a model in a blue
t-shirt. They are never the default; eventually they become a per-exercise
opt-in for people who want to see the real setup.

Note `Routine.sourceAssets` is *planned* in the prior spec and **still not
shipped**, even though most of that delivery plan has since landed. `Routine`
today carries `id / name / createdAt / isActive / exercises / phaseStorage /
previousVersionID`. `Asset` and `Exercise.media` remain in the schema, written
by nothing. So the sheet images have no storage behind them, and "use the
picture from my sheet" appears in the picker only once they do.

### Sheet text only — generation is deferred

A generated HEP carries labelled **Setup / Movement / Tip** prose. Capture it
and attribute it to the sheet. The phone writes nothing for now.

This matters structurally: `SessionView:95` renders `Exercise.notes` beside the
running timer, so any text written there reaches the user mid-exercise. When
generation is eventually added, it must be barred from that path, not merely
labelled.

### Art downloads once, on first launch

The subset is not baked into the binary. It is fetched on first run and cached,
keeping the app small. **No network at exercise time** — once cached, the art
is local forever. The first run needs a progress state and a failure path, and
an exercise whose art hasn't arrived yet shows no picture rather than a
placeholder.

### The flow

> set up → see the suggested pictures in the list → go edit any that are wrong
> → save → see it while doing the exercise

## Constraints

- **Coverage is thin exactly where PT handouts are thick.** Of 302 exercises,
  only **14 are stretches**; 135 are barbell / dumbbell / machine / cable gym
  movements a handout will never name. The reference sheet's very first
  exercise, *Slant Board Gastrocnemius Stretch*, has no entry. Expect misses,
  and design the miss as a normal state.
- **No synonyms in the catalogue.** The manifest has `slug`, `name`,
  `exerciseType`, `equipment`, `primaryMuscle`, `secondaryMuscles`, `isStretch`
  and per-frame attribution — no alternate names. Bridging "quadruped opposite
  arm/leg raise" to `bird-dog` is the matcher's job, not the data's.
- **Size.** Measured: the 142-exercise subset is **13.3 MB** of PNG against
  **31.0 MB** for all 302. All 14 stretches survive the cut.
- **Licence.** CC BY-SA 4.0 requires attribution and share-alike on *modified
  artwork*. Resolved by the delivery decision: jsDelivr serves the npm
  package's **original PNGs** (`@bryllim/workout-guide@1.0.0/assets/<slug>/frame-N.png`,
  confirmed 200, 26 KB for `bird-dog/frame-1`) and the manifest; SVG is not in
  the package and 404s there. Downloading the originals untouched is plainly
  unmodified, and render-time tinting via `.renderingMode(.template)` is not
  modification either. No format conversion, so share-alike never attaches.
- **Apple's on-device model is text-only.** `FoundationModelsExtractor` already
  establishes the pattern: `@Generable` / `@Guide`, gated on
  `SystemLanguageModel.default.availability`.
- `CLAUDE.md` applies in full: `@Observable`, `NavigationStack`, async/await,
  no force-unwraps, semantic colours, Dynamic Type, XCTest + ViewInspector, no
  new package dependencies without asking.

## Shape of the work

### Where the picture appears

| Surface | What it shows |
|---|---|
| Today's routine list (`ExerciseRowView`) | One frame, thumbnail scale, leading the row |
| Session (`SessionView`) | One frame, large, above the name; must not crowd the timer |
| Exercise screen (`ExerciseProgressView`) | Large frame, scrub to the other two, the sheet's how-to text, attribution |
| Exercise editor (`ExerciseEditorView`) | Current pick + the control to change it — serves import review *and* after-save correction |

All four already exist. `ExerciseProgressView` is reached from the Progress
tab's exercise list, which is already a `NavigationStack` with a
`Route.exercise(UUID)`. The editor is reached from Today's Edit menu.

The user's flow — *see the suggested pictures in the list → go edit any that
are wrong → save* — maps onto Today's list and its existing Edit menu. Rows do
not need to become tappable.

### Matching

Two stages, because 302 candidates will not fit usefully in one prompt:

1. **Narrow, cheaply and locally.** Normalise the parsed name and score it
   against catalogue names and muscle / equipment terms. Keep a handful.
2. **Rank, with the on-device model.** Give it the parsed name, the sheet's own
   notes, and the candidate list. Return a ranked subset with **"none of these"
   as a first-class option** — constrained generation via `@Generable` so it
   must choose from the candidates rather than inventing a slug.

**When the shortlist is empty or weak, stage 2 gets the whole catalogue
instead.** Lexical scoring cannot bridge a clinical name to a common one:
"Quadruped Opposite Arm/Leg Raise" shares no token with "Bird Dog", and does
share tokens with "Lying Leg Raise". Narrowing on a weak signal therefore
discards the right answer before the model ever sees it — and discards it
precisely for the handout phrasing this feature exists to handle. All 142 names
are a few KB of prompt, once per routine.

Stage 2 is skipped when the model is unavailable; stage 1's top candidate
becomes the suggestion *if it clears the floor*, and the rest become the
alternatives. **The feature must degrade to stage 1 alone**, never to nothing.

### Sheet text

Extend parsing to capture labelled instruction prose per exercise and keep its
provenance. The reference handout's Setup / Movement / Tip is the shape to aim
at; the parser should not require those exact labels.

## Calls I made

Flagged so they can be overridden cheaply.

- **Ship a 142-exercise subset** — bodyweight, resistance band, wall, towel,
  doorway, chair, box, stability ball. The excluded 160 are gym equipment.
- **Reference frames by slug, not file URL.** `Asset.urlString` is a loose
  `String`. Use a scheme such as `library://<slug>/<frame>` so library art and
  user-supplied images coexist without a migration.
- **The chosen picture rides on `ParsedRoutine.ParsedExercise`, not only on the
  persisted `Exercise`.** `toRoutine()` builds fresh `Exercise` objects with
  `media: []`, so a pick that lives only on the model is silently wiped by any
  later save through the import editor.
- **A new `MediaKit` target** owning the catalogue, the matcher, and asset
  resolution, depending on `DataKit`. Keeps `ParsingKit` about parsing. This
  adds a second `FoundationModels` import; the comment in
  `FoundationModelsExtractor.swift` claiming it is the only such file needs
  updating.
- **Matching runs during import, one call per exercise.**
  `SetupViewModel.withSuggestedArt` fans out one `matcher.match` per exercise in
  a task group, each stage-2 call building its own `LanguageModelSession`, so
  suggestions are ready when the review screen appears. (An earlier draft of this
  spec said "batched, one model call for the routine"; that is not what was
  built.) On-device inference is effectively serialised, so N exercises means N
  sequential inferences, each carrying a prompt measured at ~6.2 KB when
  widened. `matchTimeout` (provisionally 20 s) must be derived from that total,
  not from a single call. Exercises that miss the deadline stay `.unmatched`
  (retryable from the picker). If it proves too slow, the fix is to batch into
  one call or fill matches in after the editor appears, not a bigger timeout.
  The import's alternatives are carried into the picker so it need not re-match
  on the review path; after save, the picker re-matches on demand.
- **An unconfirmed guess reads as a guess** in the review step only; once saved
  it is just the picture.
- **Attribution screen in Settings**, linked from the exercise screen.

## Left to the builder

- Normalisation and scoring for stage 1 — no synonyms in the catalogue, so this
  needs real test cases drawn from actual handout phrasing.
- Prompt and `@Generable` shape for stage 2, following the existing extractor.
- The download-and-cache mechanism, its first-run UI, and its failure path.
- Thumbnail, session and exercise-screen layout within the Swiss + Glass
  system, at accessibility text sizes.
- Whether the frame scrub is a gesture, a segmented control, or both.
- VoiceOver treatment. A decorative figure should not be announced as content;
  the sheet's how-to text should be.
- Where the catalogue subset is generated and how it is regenerated when the
  upstream library updates.

## Open questions for later

- Stretch coverage is the weak point (14 entries). Worth revisiting whether a
  second source fills that gap.
- Does a user's hand-fixed picture survive a re-import when the PT hands over a
  new sheet? `Exercise.lineageID` and `RoutineChanges` already exist to match
  exercises across versions, so carrying the art across a phase is now a small
  change — but it is not in this spec.

## What this spec relies on, already shipped

PDF and image import (`RoutineDocument`), in-place routine editing
(`EditRoutineView`), the Progress tab with its per-exercise screen
(`ExerciseProgressView`), routine versioning with lineage IDs, and the Mend
rename. The only thing this spec adds to the app's structure is `MediaKit`.
