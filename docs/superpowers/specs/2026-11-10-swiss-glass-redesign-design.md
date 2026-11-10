# Eccentric — Swiss + Glass redesign and v1 UX

Design canvas: https://claude.ai/artifact/KfaaDQ5nDabCfxp5GeTJ9P (see `docs/design/README.md`).

## Context

The June spec (`2026-06-14-pt-app-design.md`) shipped a black/white, mono,
safety-yellow app with one routine, a streak and a heatmap. This spec takes
that further on two fronts:

1. **Visual system:** "Swiss + Liquid Glass." Content is set like print:
   grotesk type, a strict grid, hairline rules, numbered tables. Controls
   (tab bar, toolbar buttons, session controls, sheets) are iOS 26 Liquid
   Glass. The rule of thumb: *content is print, chrome is glass.*
2. **UX:** the app grows from "do today's routine" to the full PT loop.
   That covers several routines with their own schedules, optional
   per-exercise ratings, routine versions when the PT hands over a new
   sheet, and a "Prepare for your visit" report to share with the PT.

## Users and moments

The app is used in four distinct moments, and each screen should be designed for one of them:

1. **On the floor, mid-exercise.** The phone is propped up 1–2 m away and
   your hands are busy. The session must be readable from across the room
   and must work without taps. Voice cues are on by default.
2. **The morning glance.** "What's due today, and how is my week going?" in five seconds.
3. **After an appointment.** A new or updated sheet arrives every few
   weeks. History must carry across phases.
4. **Before or at the appointment.** The PT cares about pain, difficulty
   and adherence more than streaks.

## Principles

- **Two modes.** Glance screens (Today, Progress, Routines) are editorial
  and information-dense. Do screens (the session) show one huge number,
  one action, color as the timer and glass controls in thumb reach.
- **Sound and haptics come first in a session.** Voice cues ("Switch
  sides", "3, 2, 1"), auto-advance and haptics. A good session doesn't
  need you to look at the screen.
- **The PT's sheet is the source of truth.** Keep the original images.
  Every parsed exercise is one tap from where it came from.
- **Kind consistency.** Weekly goals per routine rather than daily streak
  pressure. Rest days are part of the plan. No guilt copy, and nothing
  turns red for being late.
- **Record how it felt.** One-tap ratings (easy / about right / hard /
  painful) feed progress and the PT report. Always optional.

## Visual system

**Color**

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` | `#F3F2EE` (paper) | `#0E0E0D` | Backgrounds |
| `ink` | `#111111` | `#F3F2EE` | Text, rules, dark-glass tint |
| `inkSecondary` | `#57564F` | `#A3A29B` | Labels, metadata (≥4.5:1 on surface) |
| `hairline` | `#D9D8D3` | `#2A2A27` | Row dividers |
| `accent` | user choice | same | Timer field, today marker, start affordance |

Accent options are **Signal `#FF5A1F`** (default), **Sky `#3FA9F5`**,
**Sun `#FFC531`**, **Mint `#2BD99F`**, **Blossom `#FF7EB6`** and **Lilac
`#A98BFF`**. Every option keeps *ink* text at ≥4.5:1, so text on the
accent is always ink, never white. Users pick in Settings › Appearance.

**Type.** Display and body use the system grotesk (SF Pro) with tight
tracking: large titles −4%, numbers −6%. Labels, metadata and
prescriptions ("3×12 L/R") use the bundled JetBrains Mono in caps with
+6% tracking. The mockups use Inter Tight and IBM Plex Mono. We use SF
Pro + JetBrains Mono so we don't add fonts. Revisit only if the result
feels off on device.

**Layout.** 20pt screen padding, a 2pt ink rule under the masthead, 1pt
ink rules between sections, hairlines between rows, numbered sections
("01 — TODAY"). No cards and no shadows on content.

**Glass.** Use the system Liquid Glass APIs (`glassEffect`, `.glass` /
`.glassProminent` button styles), not hand-rolled blur. There are two
weights. **Clear glass** is for toolbar circles and the tab bar. **Ink
glass** (tinted near-black) is for the one primary action on a screen.
Glass sits over content or color, never as decoration on plain surface.

**The session timer.** The time left is a block of accent color that
drains from the bottom of the screen (height = remaining ÷ total). The
seconds sit across its top edge in ink at ~180pt, and the glass controls
float over the color. Rest uses the same field. Rep sets show the rep
count instead of a field.

## Information architecture

Three tabs (Today · Progress · Routines), with Settings reached from
Routines. Import is a sheet you can open from anywhere (the "+" on Today,
or the share sheet).

## Screens (v1)

**Today:** what's due across routines ("Morning mobility · 1 of 2
today", "Knee strength · 2 of 3 this week"), a "Not due today" line (do it
early), a next-PT-visit strip with "Prepare", and a glass "Up next"
accessory above the tab bar.

**Session (full screen):**
- Get ready (3-2-1 plus a setup cue)
- Timed hold
- Reps (long-press Done to log a different count)
- Rest
- Switch sides
- Optional rating sheet during rest, which closes when rest ends
- Paused / resume (an interruption saves; reopening within a few hours offers resume)
- Exercise list overlay (jump, skip, reorder)
- Summary: catch-up ratings for unrated exercises, 0–10 pain, a note, saved to Apple Health

**Progress:** weekly goals per routine, exercise detail (progress
across phases, ratings, the original sheet crop), history, and Prepare for
your visit (one page since the last appointment: consistency, progress
deltas, "worth discussing" flags and pain notes; shared as a PDF or shown
full screen).

**Routines:** active and archived phases, routine detail (schedule,
exercises, reminders, original sheets, "Replace with new version"),
exercise editor, and schedule editor (times per week, days, sessions per
day, reminder).

**Import (a sheet):**
1. **Source:** camera document scanner, photos, PDF, or the share sheet.
2. **Read on-device.**
3. **Review:** uncertain values are highlighted with a one-tap fix and "see on sheet".
4. **What changed:** shown only when the sheet matches an existing routine. It counts added, changed, removed and unchanged exercises, then offers "Replace Phase N" or keep both.
5. **Schedule and reminder.**

**Settings:**
- Appearance (accent)
- Session cues (voice on by default, haptics, sounds, auto-start rest)
- Rate exercises (after each by default, at the end, or off)
- Reminders
- Apple Health
- Data

## Key flows

1. **First run:** import → review → schedule → Today. Aim for a first session within two minutes.
2. **Daily session:** reminder, Today or Watch → session → optional ratings → summary → Health.
3. **Hands-free:** the giant timer plus voice and haptics. Start from the Watch or the lock-screen Live Activity.
4. **Interrupted:** it pauses and saves. Within a few hours you're offered resume; after that it's kept as partial.
5. **After an appointment:** the new sheet is imported, the changes reviewed and the routine replaced. Charts continue across phases.
6. **Before an appointment:** Prepare for your visit → share.

## Data model implications

All of these are additive to the June model:

- `Routine` gains a `schedule` (times per week or days, sessions per
  day, reminder time), a `phase` / `previousVersionID` for versioning, and
  `sourceAssets` (the original sheet images, using the existing `Asset`).
- `ExerciseRecord` gains an optional `rating` (easy / right / hard /
  painful) and the actual reps or seconds when they differ from the target.
- `SessionRecord` gains optional `pain` (0–10) and `note`.
- A new `Appointment { date, notes }` anchors "since your last visit".
- Exercises match across versions by a stable lineage ID, assigned on
  import and kept when names match, so progress charts span phases. A
  rename on a new sheet shows as remove + add unless the user links them
  in review.

## Delivery plan

Each step is one PR, and each leaves `main` shippable.

1. **Visual system + restyle of current screens (this PR).** Tokens,
   type, glass components and accent preference. Home → Today (single
   routine), the session with the color-field timer and glass controls,
   Complete, and Settings › Appearance. No data-model changes.
2. **Several routines + schedules.** `Routine.schedule`, the Today due
   list, per-routine reminders and weekly goals. Tab bar with Routines.
3. **Ratings + summary.** Rating fields, the rating sheet, the Settings
   choice, and the summary screen with catch-up ratings, pain and a note.
4. **Import review + versions.** Keep the source images, report
   uncertain fields from the parser, add the review UI, plus diff and replace.
5. **Appointments + Prepare for your visit.** `Appointment`, the report
   view and PDF export (`ImageRenderer`).
6. **Progress tab:** overview, exercise detail, history.
7. **Later:** Watch session, Live Activity, widgets, Siri / App
   Intents, "Taking a break" mode.

## Known issues (not in this PR)

- `SessionEngine` only checks pause between sets, so a timed set keeps
  counting down while paused. The visual timer mirrors the engine. Fixing
  pause properly belongs with the session work in step 3.

## Open questions

- Private notes: should some session notes stay out of the PT report?
- Whether to adopt Inter Tight / IBM Plex Mono to match the mockups exactly.
