---
name: ios-testflight-ci
description: Set up, adapt, or debug GitHub Actions CI for an iOS app — a test workflow on every PR plus a manual "Ship TestFlight" workflow that signs with an Apple Distribution certificate and uploads to App Store Connect, with no Mac needed. Use when adding CI or TestFlight shipping to a new iOS repo, when wiring up Apple Developer / App Store Connect (API key, distribution certificate, bundle IDs, app record, TestFlight groups), when adding an app extension or capability to the ship workflow, or when a CI/TestFlight run fails (signing, provisioning profiles, duplicate build numbers, simulator stalls).
---

# iOS CI + TestFlight on GitHub Actions

A two-workflow setup, proven in the Mend (physical-therapy-app) repo, that lets
someone with no Mac build, test, sign and ship an iOS app:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | every PR, every push to `main` | generate project → build app → run tests → assert every test bundle ran |
| `ship-testflight.yml` | manual (Actions → Run workflow), `main` only | set build number → import dist cert → fetch/create App Store profile via API → archive → export IPA → verify build number → upload |

The flow for contributors: branch → PR → CI green → merge → run **Ship
TestFlight** when you want a build → it appears in TestFlight 5–15 min later.

## Design decisions (keep these unless you have a reason)

1. **Manual signing with one shared Apple Distribution certificate.** Never
   automatic signing on CI: each fresh runner mints a new Apple *Development*
   certificate until the team hits Apple's cap and archives start failing.
   Release configs are `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Apple
   Distribution"`, profile passed in as a build setting. Debug stays automatic.
2. **Profiles are fetched, not stored.** `templates/appstore_profile.rb`
   (Ruby stdlib only — every macOS runner has it) uses the App Store Connect
   API key to: register the bundle ID if asked, enable capabilities
   (e.g. `HEALTHKIT`), find the distribution cert by serial, reuse a valid
   profile or delete stale ones and create a new one, install it, and emit
   `uuid=` to `$GITHUB_OUTPUT`. No fastlane, no match repo, no profile secrets.
3. **Secrets live on a `testflight` GitHub environment restricted to
   `main`**, not on the repo. A workflow edited on a feature branch cannot read
   the signing key.
4. **CI always runs (no `paths-ignore`)** so it can be a required check;
   a path-filtered required check stays Pending forever on doc-only PRs.
5. **Pin the bundle set, not a test count.** CI greps the log for
   `Test Suite '<Bundle>.xctest' passed` for each expected bundle. A run that
   silently drops a bundle otherwise looks green.
6. **Pin `arch=arm64` on the simulator destination** and pick the simulator
   by querying `simctl`, not by name. Runners list each simulator twice
   (arm64 + Rosetta); landing on Rosetta stalls the test step silently.
7. **Build number = `github.run_number + BUILD_NUMBER_OFFSET`**, and the
   workflow unzips the IPA and fails *before* upload if `CFBundleVersion`
   doesn't match. Info.plist must read `$(CURRENT_PROJECT_VERSION)` /
   `$(MARKETING_VERSION)` — XcodeGen otherwise writes literals and every upload
   after the first is rejected as a duplicate.
8. **Team-level secrets are reused across repos.** One API key and one
   distribution certificate serve every app on the team. Apple caps
   distribution certificates (a handful per team), so don't make one per repo.

## Setting up a new repository

Work through these in order. Steps 1–2 are code changes you (Claude) make;
steps 3–5 are things the user does in Apple's and GitHub's web UIs — walk
them through it, using the reference docs, and don't claim they're done.

### 1. Survey the target repo

Find, and confirm with the user where ambiguous:

- **Project generation:** XcodeGen `project.yml`? Tuist? A committed
  `.xcodeproj` only? (Templates assume XcodeGen; see "Without XcodeGen" below.)
- **App name, scheme, project path**, and the **app target's bundle ID**.
- **Every extension target** (widgets, Live Activities, share extensions…) and
  its bundle ID — each needs its own profile.
- **Capabilities/entitlements** on each target (`*.entitlements`), mapped to
  App Store Connect `capabilityType` values (e.g. `HEALTHKIT`, `APP_GROUPS`,
  `PUSH_NOTIFICATIONS`, `ICLOUD`, `ASSOCIATED_DOMAINS`).
- **Team ID** (10 chars; `DEVELOPMENT_TEAM` in the project, or ask).
- **Test layout:** which scheme runs tests (an SPM package scheme like
  `MyCore-Package`, or the app scheme), and the exact list of `.xctest`
  bundle names it should produce.
- **Deployment target / SDK:** App Store Connect requires the current iOS SDK
  (Xcode 26 / iOS 26 SDK as of this writing). Update the `Select Xcode` step
  and SDK floor if the year has moved on.

### 2. Add the files

Copy from `templates/` and replace every `__PLACEHOLDER__`
(`grep -rn '__[A-Z_]*__'` afterwards must find nothing):

| Template | Goes to | Placeholders |
|---|---|---|
| `templates/ci.yml` | `.github/workflows/ci.yml` | `__PROJECT_DIR__`, `__XCODEPROJ__`, `__APP_SCHEME__`, `__TEST_DIR__`, `__TEST_SCHEME__`, `__TEST_BUNDLES__` |
| `templates/ship-testflight.yml` | `.github/workflows/ship-testflight.yml` | `__APP_NAME__`, `__PROJECT_DIR__`, `__XCODEPROJ__`, `__APP_SCHEME__`, `__BUNDLE_ID__`, `__CAPABILITIES__`, `__IPA_NAME__` |
| `templates/appstore_profile.rb` | `ci/appstore_profile.rb` | none — copy verbatim |
| `templates/ExportOptions.plist` | `ci/ExportOptions.plist` | `__TEAM_ID__`, `__BUNDLE_ID__` |
| `templates/project-signing.yml` | merge into `project.yml` (fragments, not a full spec) | `__TEAM_ID__`, `__BUNDLE_ID__` |

`__TEST_BUNDLES__` is a space-separated list (`CoreTests UITests`).
`__CAPABILITIES__` is comma-separated (`HEALTHKIT,APP_GROUPS`) — delete the
`CAPABILITIES=` line if there are none. The archive step's profile variables
(`APP_APPSTORE_PROFILE`, `WIDGETS_APPSTORE_PROFILE`) must match the names in
each target's `PROVISIONING_PROFILE_SPECIFIER`.

Then:

- **Per extension:** duplicate the "Fetch widget extension provisioning
  profile" step (pass `BUNDLE_NAME` so the script registers the ID), add a
  `<EXT>_APPSTORE_PROFILE=` build setting to the archive command, a `PlistBuddy Set`
  line to the export step, and a key to `ExportOptions.plist`. Give the
  extension target the same Manual/Release signing block. Delete the widget
  step entirely if there are no extensions.
- **Info.plist** for *every* target: `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`,
  `CFBundleShortVersionString: $(MARKETING_VERSION)`. Set
  `ITSAppUsesNonExemptEncryption: false` if true for the app (skips the export
  compliance prompt on every build). Make sure there's an **app icon**
  (`CFBundleIconName` + an asset catalog `AppIcon` with a 1024px image) — the
  first upload is rejected without one.
- **`IPA_NAME`** is the *product name* of the app target (often the target
  name, e.g. `PTApp.ipa`), not the display name. If unsure, have the workflow
  `ls build/export` once.
- **`BUILD_NUMBER_OFFSET`**: 0 if nothing was ever uploaded for this app;
  otherwise set it above the highest existing build number.
- Add `build/`, `*.ipa`, `*.dSYM*` to `.gitignore`.
- Add a `CONTRIBUTING.md` section describing the loop (see this repo's).

### 3. Apple Developer + App Store Connect (user does this)

Follow `references/apple-setup.md`. In short:

1. Program membership active; latest agreements accepted.
2. App Store Connect **API key** (Team key, Admin or App Manager) → Key ID,
   Issuer ID, `.p8`. *Reuse the team's existing key if there is one.*
3. **Apple Distribution certificate** exported as `.p12` with a password.
   *Reuse the team's existing one if there is one* (doable on Windows/Linux
   with `openssl`; recipe in the reference).
4. Register the **app's bundle ID** and create the **app record** in App
   Store Connect. (Extensions' bundle IDs the script can register itself.)
5. Create an **internal TestFlight group** and add testers.

### 4. GitHub (user does this)

Follow `references/github-setup.md`:

1. Environment `testflight`, deployment branches = `main` only, with the five
   secrets: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_API_KEY_P8`, `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`.
2. Branch ruleset on `main`: require a PR and the `test` status check.
3. Be aware: macOS runner minutes bill at a multiple of Linux on private repos.

### 5. Verify

1. Open a PR with the new files. CI must go green and print every bundle
   as passed. (It can't be a required check until it has run once.)
2. Merge. Run **Ship TestFlight** from `main`. First run is the real test of
   the Apple setup — read failures with `references/troubleshooting.md`.
3. Confirm the build shows in App Store Connect → TestFlight, then answer any
   compliance question and check the internal group received it.
4. Run Ship TestFlight a second time: it must reuse the profile ("Reusing
   profile…") and upload build N+1 without errors.

## Without XcodeGen

- Delete the `Install XcodeGen` / `Generate project` steps.
- Replace the `sed` on `project.yml` in "Set build number" with passing
  `CURRENT_PROJECT_VERSION="$BUILD"` on the `xcodebuild archive` line
  (Info.plist must still use `$(CURRENT_PROJECT_VERSION)`).
- Set Release signing in the Xcode project (Signing & Capabilities → uncheck
  Automatic for Release; or `CODE_SIGN_STYLE = Manual`,
  `CODE_SIGN_IDENTITY = "Apple Distribution"`,
  `PROVISIONING_PROFILE_SPECIFIER = "$(MYAPP_APPSTORE_PROFILE)"` in the
  Release build settings / an `.xcconfig`).

## Changing an existing setup

- **New capability** on a target → add its `capabilityType` to that step's
  `CAPABILITIES` (comma-separated). The script enables it and regenerates the
  profile, since a capability change invalidates old ones.
- **New extension** → see "Per extension" above. Six touch points; miss one
  and export fails with "no profile for …".
- **Bumping the marketing version** → edit `MARKETING_VERSION` in
  `project.yml` for every target. Build numbers keep counting up.
- **Certificate renewal** (yearly): create a new distribution cert, update
  `DIST_CERT_P12_BASE64` / `DIST_CERT_PASSWORD` in every repo using it. The
  script finds the new cert by serial and replaces the profiles itself.

When a run fails, read `references/troubleshooting.md` before changing
anything — most failures there have already happened once.
