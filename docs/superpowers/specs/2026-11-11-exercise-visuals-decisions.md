# Mend — exercise visuals: decisions made during implementation

Companion to `2026-11-11-exercise-visuals-design.md` and
`../plans/2026-11-11-exercise-visuals.md`. These are the calls made while
building, in order, each with why and what it costs if wrong. Several changed
the design mid-flight; they are recorded here so the reasoning outlives the
branch.

## Design changes

**Stage 2 is given the whole catalogue when stage 1's shortlist is weak.**
Lexical scoring cannot bridge a clinical name to a common one: "Quadruped
Opposite Arm/Leg Raise" shares no token with "Bird Dog" and *does* share
tokens with "Lying Leg Raise". Narrowing on a weak signal therefore threw away
the right answer before the model saw it — for exactly the handout phrasing
this feature exists to handle. When the shortlist is empty or its top score is
below `wideningThreshold` (0.6), the ranker gets all 142 entries instead.
Measured afterwards: real handout phrasings score 0.738–1.000, the clinical
synonym tops out at 0.398, so the threshold sits in a genuine gap.
*Cost if wrong:* larger prompts and more chances for the model to pick
something plausible but wrong; the floor and one-tap correction still apply.

**`ArtChoice.none` may only be returned when something actually decided.**
`ExerciseMatcher` fell back to stage 1 when the on-device model was
unavailable, and stage 1 returned `.none` below the floor — which means "no
picture wanted" and is *not* retryable. On a phone without the model, every
weakly-matching exercise was permanently blanked. The stage-1-only path now
returns `.unmatched`. Programmatic `.none` has exactly one construction site:
an available ranker declining. The user tapping "No picture" is the only other.
*Cost if wrong:* exercises with genuinely no match stay retryable, costing a
later re-match rather than a permanent blank.

**The ranker answers with indices, not slugs.** A small model copying
`side-lying-hip-abduction` out of a 142-line list sometimes mangles it, and
every mangle was a silent discard that fell back to stage 1 and usually ended
in no picture — undoing the synonym rescue the stage exists for. Candidates are
numbered; the model returns `[Int]`; the hallucination guard became a bounds
check. *Cost if wrong:* the model miscounts rows instead of mistyping slugs,
and the bounds check still blocks anything invalid.

**The accept/reject rule the prompt states.** Accept when an exercise differs
only in support, prop, equipment, side or starting position; reject when the
joint action, direction of movement, or muscle worked differs. An earlier
instruction to reject "Wall Squat" → a plain squat was withdrawn: it
contradicted the product decision that an adjacent picture is a good offer
corrected in one tap. *Note:* the prompt still contains a "sharing a word such
as 'squat' is not enough" line that reads as a conflict, and there is no bare
`squat` slug — the catalogue has `bodyweight-squat`. Both need the device check.

**"Copy verbatim" is enforced in code, not by prompt.** The sheet's how-to text
was protected only by asking the model not to paraphrase. A model that rewords
a physiotherapist's form cue *is* writing, which the design forbids. A section
is now dropped unless its normalised body is a substring of the sheet's own
text, and `source` is a required parameter so no call path can skip the check.
Normalisation forgives typography (NFKC, soft hyphens, line-break hyphens,
quotes, dashes) and refuses wording. *Cost if wrong:* a legitimate section is
occasionally dropped; nothing invented can ever appear.

**The picker takes the sheet's notes.** Import matched with notes; a picker
that re-matched without them produced different suggestions, making the
import's own choice more likely to fall out of the list — exactly when the user
needs to see it. Diverges from the plan's stated interface for that view.

**The picker always lists the current choice**, computed synchronously, even
when a fresh match no longer suggests it. Otherwise a corrected picture showed
no selection on reopen — the likely case, since the user corrected it precisely
because the matcher had not chosen it.

**The session figure collapses unless art is `.library`;** Today's list keeps a
fixed 44pt gutter. No picture is ever coming for `.none`/`.unmatched`, so the
reserved square only pushed the timer down on the screen read from across a
room. The list is the opposite case: the gutter keeps columns aligned.

**The scrub and licence credit appear only once a frame has actually loaded.**
Gating on catalogue membership alone meant an offline first launch showed a
dead Start/Middle/End control and a credit for an absent illustration over a
blank square.

**`ArtStore.prefetch` was deleted.** No production caller; reintroduce it
deliberately when something needs it.

## Known-wrong and deferred

**Matching runs once per exercise, not once per routine.** The spec originally
claimed batching. On-device inference is effectively serialised, so N exercises
means N sequential inferences, each with a ~5.9 KB widened prompt, inside one
`matchTimeout` (now 20s, provisional). This puts the prior spec's two-minute
first-session target at risk. **The right fix is batching into one call, or
filling matches in asynchronously after the editor appears — not a bigger
timeout.** Decide it with measurements from a real device.

**`AppFont.mono` does not scale with Dynamic Type.** It uses
`Font.custom(_:fixedSize:)` at every call site across the app —
`SectionLabel`, Home, Progress, Settings, Complete. Pre-existing, app-wide, and
against this project's own Dynamic Type rule. Deliberately untouched here;
deserves its own change.

**The committed `App/PTApp.xcodeproj/project.pbxproj` is stale.** Regenerating
it pulls in `PTApp.entitlements`, `Apple Distribution` signing, manual code-sign
style and `$(MEND_APPSTORE_PROFILE)` — changes from the TestFlight work that
were never regenerated into the committed file. Left alone rather than bundled
into this branch.

## Still unverified — needs a real device

The on-device model is not available in the simulator, so every matcher test
uses a stub. Nothing here has been seen working against Apple's actual model.

1. Does "Quadruped Opposite Arm/Leg Raise" reach `bird-dog`? Does "Wall Squat"
   reach `bodyweight-squat` (now a ruled accept)? Does "Slant Board
   Gastrocnemius Stretch" correctly answer none?
2. Does `LanguageModelSession.respond` honour cancellation? If not, the import
   deadline never bites, because `withTaskGroup` awaits every child regardless.
3. How long does one inference actually take? That decides the timeout and
   whether batching is needed.
4. Session layout on an iPhone SE at default and accessibility text sizes: does
   the timer stay dominant, and does the Rest transition move it?
5. Today's rows at larger Dynamic Type, with the 44pt figure and 30pt number
   columns fixed, and the row alignment changed from `.firstTextBaseline` to
   `.center`.
