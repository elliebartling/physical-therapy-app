# Troubleshooting

Each entry: the symptom as it shows in the log, the cause, the fix. The
first group are failures that actually happened while building this
pipeline; the rest are the usual first-run Apple setup mistakes.

## Already hit once

**Test step hangs with no output until the 20-minute job timeout.**
xcodebuild picked the x86_64/Rosetta copy of the simulator (runners list
each one twice). Pin `arch=arm64` in every `-destination`, pick the
simulator by UDID from `simctl`, and don't pipe through `| tail` (it hides
output until the step ends). Give the test step its own `timeout-minutes`.

**CI is green but a whole test bundle never ran.**
A target dropped out of the scheme/package. The "Assert every test bundle
ran" step exists for this; when adding a test target, add it to
`__TEST_BUNDLES__` in the same PR.

**Upload rejected: "The bundle version must be higher than the previously
uploaded version" / duplicate build 1.**
Info.plist had a literal `CFBundleVersion` (XcodeGen writes `"1"` unless
told otherwise), so the CI build number never reached the app. Use
`$(CURRENT_PROJECT_VERSION)` / `$(MARKETING_VERSION)` in every target's
Info.plist. The "Check IPA build number" step catches this before upload.
If builds were uploaded outside this workflow, raise `BUILD_NUMBER_OFFSET`
above the highest existing number.

**Archive fails: "You already have a current Apple Development certificate"
/ "maximum number of certificates", or each run adds a certificate in the
portal.**
Automatic signing on a fresh runner. Release must be `CODE_SIGN_STYLE:
Manual` with `Apple Distribution` for *every* signed target, including
extensions. Revoke the junk *Development* certificates CI created
(Certificates list, filter by Development, created by the API key) — not
the Distribution one.

**First upload rejected: missing app icon / `CFBundleIconName`.**
Add an `AppIcon` asset catalog with a 1024×1024 PNG,
`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, and `CFBundleIconName:
AppIcon` in Info.plist.

**"Upload rejected: SDK version" / built with an older SDK.**
App Store Connect requires the current iOS SDK. The ship workflow selects
the newest `Xcode_26*` and checks the SDK floor; bump both when Apple moves
the requirement (usually each April).

## Signing and profiles

**`appstore_profile.rb`: "The distribution certificate … isn't an active
certificate in this App Store Connect account."**
The `.p12` is from another team, or the cert was revoked/expired. Check the
Team ID on the cert and in the portal; re-export or make a new one.

**`appstore_profile.rb`: 401 / 403 from App Store Connect.**
401: Key ID, Issuer ID, or `.p8` don't belong together (or the `.p8` lost its
BEGIN/END lines or newlines). 403: the key's role is too low (needs Admin or
App Manager with Certificates/Identifiers access), or an agreement is
pending acceptance.

**`appstore_profile.rb`: "Bundle ID … isn't registered in this account."**
Register the app's bundle ID in the portal (apple-setup §4), or pass
`BUNDLE_NAME` so the script registers it.

**`security import` fails: "MAC verification failed during PKCS12 import"
or wrong password.**
Wrong `DIST_CERT_PASSWORD`, a base64 value with line breaks/whitespace, or
a `.p12` made with OpenSSL 3 defaults. Re-export with `openssl pkcs12
-export -legacy …` and re-encode on one line.

**Archive: "No profile for team … matching '…' found" or "requires a
provisioning profile" for an extension.**
An extension isn't wired up at all six places: profile-fetch step, archive
build setting, `PROVISIONING_PROFILE_SPECIFIER` in its Release config,
`PlistBuddy Set` line, `ExportOptions.plist` key, and its bundle ID. The
profile variable name must match between workflow and project.yml.

**Archive: "Provisioning profile … doesn't include the X capability /
entitlement".**
The entitlement is in the target but its `capabilityType` isn't in that
step's `CAPABILITIES`. Add it; the script enables it and regenerates the
profile. Capabilities that need IDs (App Groups, iCloud) must also be
configured in the portal.

**Export: "exportArchive: No signing certificate 'Apple Distribution'
found".**
The keychain wasn't in the search list or the partition list wasn't set.
Check the import step's `find-identity` output lists one valid identity.
Download the `signing-diagnostics` artifact for the `.xcdistributionlogs`.

## Upload and TestFlight

**`altool`: "No suitable application records were found."**
No app record in App Store Connect for this bundle ID (apple-setup §5), or
the record's bundle ID differs from the built one.

**Upload succeeds but the build never appears.**
Processing takes 5–15 min, sometimes longer. Check the email of the
Account Holder/Admins: Apple mails "ITMS-…" issues (missing usage
description strings like `NSCameraUsageDescription`, invalid icons) after
processing, not during upload.

**Build stuck on "Missing Compliance".**
Answer it in TestFlight, and add `ITSAppUsesNonExemptEncryption: false` to
Info.plist if the app only uses exempt encryption (HTTPS, system crypto).

**Testers don't see the build.**
They're not in a group, the group doesn't have automatic distribution, or
(external) the build is waiting on Beta App Review.

## Runner

**"Waiting for a runner to pick up this job" forever.**
The `macos-NN` label doesn't exist (yet / any more). Update `runs-on`.

**Job can't read secrets / "Missing App Store Connect secrets" on main.**
Secrets are on the repo or a differently named environment, or the
environment's branch policy doesn't include `main`.
