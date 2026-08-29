# Mend

A minimalist iPhone + Apple Watch app for physical therapy routines: photograph
your PT's exercise sheet, let on-device intelligence turn it into a structured
routine, then do the workout with guided timers, log it to Apple Health, and
watch compliance and progression over time.

Everything runs on-device — screenshots never leave your phone.

## How it works

1. **Import** — Pick screenshots of the PT sheet. The Vision framework OCRs
   them; Apple's Foundation Models framework (the on-device Apple Intelligence
   LLM) structures the text into exercises with sets, reps/holds, rest, and
   per-side flags. A review screen lets you correct anything before saving.
   No Apple Intelligence on the device? Manual entry uses the same editor.
2. **Play** — A guided session steps through each exercise: countdown rings
   and haptics for timed holds, tap-to-complete for rep sets, automatic rest
   timers, left/right alternation for per-side exercises. The Watch app runs
   the same engine with live heart rate via a HealthKit workout session.
3. **Track** — Completed sessions save to Apple Health as workouts and to a
   local SwiftData store. Trends shows weekly compliance against the
   prescribed frequency, streaks, and per-exercise progression.

## Project layout

| Path | What it is |
|---|---|
| `Mend/` | iOS app (SwiftUI): Today, Trends, Routines, import flow, player |
| `MendWatch/` | watchOS app: routine list, guided player, workout session |
| `MendKit/` | Shared sources compiled into both apps: SwiftData models, the `PlayerEngine` state machine, `ComplianceEngine`, sync payloads |
| `MendTests/` | Unit tests for the engines |
| `project.yml` | XcodeGen project definition — the `.xcodeproj` is generated, not committed |
| `ci/` | Export options for TestFlight shipping |

Routines sync phone → watch over `WCSession` application context; completed
watch sessions transfer back and merge into the phone's history (the watch
writes its own HealthKit workout, so nothing double-counts).

## Development

Requirements: Xcode 26+, and for screenshot import an Apple
Intelligence-capable device (iPhone 15 Pro or later) with Apple Intelligence
enabled. HealthKit needs a real device.

```sh
brew install xcodegen
make open        # generates Mend.xcodeproj and opens it
make test        # build + unit tests in the simulator
```

Signing: Debug builds use automatic signing with the team set in
`project.yml`. Release archives sign manually with the Apple Distribution
certificate and the named App Store profiles (below).

## CI & TestFlight

Same architecture as [read-later](https://github.com/elliebartling/read-later):

- **CI** (`.github/workflows/ci.yml`) — builds the app + watch app and runs
  the tests on every PR and push to `main`.
- **Ship TestFlight** (`.github/workflows/ship-testflight.yml`) — manual
  "Run workflow" only. Archives Release with manual signing, verifies the
  HealthKit entitlement survived, and uploads with `altool`.

One-time setup before the first ship:

1. In the developer portal, create App IDs `com.ellenbartling.mend` and
   `com.ellenbartling.mend.watchkitapp`, each with the **HealthKit**
   capability.
2. Create App Store provisioning profiles named **"Mend App Store"** (app)
   and **"Mend Watch App Store"** (watch) against those App IDs and the
   Apple Distribution certificate.
3. Create the app record in App Store Connect (bundle ID
   `com.ellenbartling.mend`).
4. Add repo secrets — the same values already used on read-later work here,
   since both apps live under the same team:
   `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_API_KEY_P8`, `DIST_CERT_P12_BASE64`,
   `DIST_CERT_PASSWORD`.

## Roadmap

- Live Activity for hold/rest timers on the lock screen (needs a widget
  extension target)
- Camera capture in the import flow (today: photo library / screenshots)
- Progression suggestions ("you've hit 3×15 for two weeks — ask your PT
  about adding resistance")
- WorkoutKit scheduling so a routine appears in the Watch's Workout app
