# Building this app well

This is a SwiftUI app for doing your physical therapy: snap a photo of a PT
handout, get a guided routine with timers and rest, keep a streak. Code here
should feel calm, modern, and small.

## How to build and test

```bash
xcodegen generate --spec App/project.yml --project App   # regenerate the Xcode project
cd Packages/PTAppCore && xcodebuild test \
  -scheme PTAppCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO                                # runs all five test suites
```

App code lives in the `PTAppCore` Swift package (`DataKit`, `ParsingKit`,
`SessionKit`, `HistoryKit`, `UI`); `App/` is a thin shell. App-target settings
go in `App/project.yml`; everything else in `Packages/PTAppCore/Package.swift`.
Never edit the generated `.xcodeproj`.

## SwiftUI, the modern way

- **State:** `@Observable` classes and `@State`/`@Bindable`. Never
  `ObservableObject`, `@StateObject`, or `@Published` in new code.
- **Navigation:** `NavigationStack` (or `NavigationSplitView`). Never
  `NavigationView`.
- **Views stay small.** When a `body` needs a comment to explain its regions,
  extract subviews. Prefer computed view properties and small structs over
  one giant body.
- **Let SwiftUI do the work.** Reach for built-in containers, `ForEach`,
  layout primitives, and modifiers before custom geometry. `GeometryReader`
  is a last resort.
- **Animation is communication.** Animate state changes that help the user
  track what happened; skip decoration. Respect Reduce Motion.

## Swift, the modern way

- **Concurrency:** `async/await` and structured concurrency only. No new GCD,
  no completion handlers where `await` works. Anything crossing an async
  boundary is `Sendable`. Keep strict-concurrency warnings at zero.
- **No force-unwraps** (`!`, `try!`) outside tests. Unwrap with `guard let`
  and fail with a real error or a sensible fallback.
- **Value types first.** Structs and enums unless identity or observation
  demands a class.
- **Errors are part of the API.** Throw typed, meaningful errors; never
  swallow one silently. If the user can't act on it, log it and degrade
  gracefully.

## Feel

- **Semantic everything:** system colors, SF Symbols, Dynamic Type text
  styles — so dark mode and accessibility sizes work for free. Test at
  larger type sizes.
- **Accessibility is not optional:** labels on symbol-only buttons,
  meaningful traits, VoiceOver-sensible ordering.
- **Haptics and sound sparingly**, at moments that matter (a set completed,
  a session finished) — never as chrome.
- This app is used mid-exercise, possibly on the floor, possibly sweaty:
  targets big, glanceable text, one obvious next action per screen.

## Testing

- XCTest (not Swift Testing), ViewInspector for view tests.
- Test behavior, not implementation. A test that breaks on a rename without
  a behavior change is a bad test.
- New logic ships with tests; bug fixes ship with the test that would have
  caught the bug.

## Restraint

- No new package dependencies without asking.
- No APIs above iOS 26 without `#available` gating.
- Don't refactor code you weren't asked to touch; leave a note instead.
