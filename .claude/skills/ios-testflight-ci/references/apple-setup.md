# Apple Developer + App Store Connect setup

Everything the ship workflow needs from Apple. Most of it is **team-level and
done once**: if the team already ships another app with this setup, reuse
its API key and distribution certificate (same five secret values) and skip
to §4.

Apple renames menus often. If a label below doesn't match, look for the
nearest equivalent rather than assuming the step is gone.

## 0. Before you start

- An active **Apple Developer Program** membership (individual or
  organization). Note the **Team ID**: developer.apple.com → Account →
  Membership details. 10 characters, e.g. `AB12CD34EF`.
- The **Account Holder** has accepted the latest agreements: App Store
  Connect → Business (and developer.apple.com → Account shows any pending
  ones). A pending agreement makes uploads and API calls fail with
  confusing 403s. Free apps don't need the Paid Apps agreement; TestFlight
  doesn't either.

## 1. App Store Connect API key

Used to fetch/create profiles (via `appstore_profile.rb`) and to upload
(`altool`).

1. appstoreconnect.apple.com → **Users and Access → Integrations → App Store
   Connect API → Team Keys**. (The first time, someone with Account Holder
   role must click *Request Access*.)
2. **Generate API Key**. Name it something like `GitHub Actions`.
   Access: **Admin** — or **App Manager** with access to Certificates,
   Identifiers & Profiles. *Developer* is not enough: it can't create
   profiles or register bundle IDs. Use a **Team** key, not an Individual key.
3. Record:
   - **Key ID** → secret `APP_STORE_CONNECT_API_KEY_ID`
   - **Issuer ID** (shown above the key list) → secret `APP_STORE_CONNECT_ISSUER_ID`
4. **Download** the `AuthKey_<KEYID>.p8`. *It can only be downloaded once.*
   Its full text, including the `-----BEGIN PRIVATE KEY-----` /
   `-----END PRIVATE KEY-----` lines → secret `APP_STORE_CONNECT_API_KEY_P8`.
5. Store the `.p8` somewhere safe (password manager). If lost, revoke and
   make a new key, then update every repo's secret.

## 2. Apple Distribution certificate (.p12)

One per team, shared by every app. Apple allows only a few distribution
certificates per team, so **reuse an existing one** if you have its `.p12`.
If one exists but nobody has the private key, revoke it only if no other
pipeline depends on it.

### Option A — on a Mac

1. Keychain Access → Certificate Assistant → *Request a Certificate From a
   Certificate Authority* → save to disk.
2. developer.apple.com → Certificates, Identifiers & Profiles →
   **Certificates → +** → **Apple Distribution** → upload the CSR → download
   the `.cer` and double-click to add it to the login keychain.
3. In Keychain Access → My Certificates, right-click
   *Apple Distribution: …* → **Export** → `.p12`, set a strong password.

### Option B — no Mac (Windows/Linux, `openssl`)

```bash
# 1. Private key + CSR
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr \
  -subj "/emailAddress=you@example.com/CN=Your Name/C=US"

# 2. Upload dist.csr at developer.apple.com → Certificates → + →
#    Apple Distribution. Download distribution.cer.

# 3. Convert and bundle. -legacy keeps the .p12 readable by macOS `security`
#    (OpenSSL 3's default encryption can fail to import with
#    "MAC verification failed" on some macOS versions).
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem \
  -out dist.p12 -passout pass:'CHOOSE-A-STRONG-PASSWORD'
```

(On OpenSSL 1.1, drop `-legacy`; it's already the default there.)

### Turn it into secrets

```bash
base64 -i dist.p12 | tr -d '\n'        # macOS
base64 -w0 dist.p12                    # Linux
[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12"))   # PowerShell
```

- That single line → secret `DIST_CERT_P12_BASE64`
- The export password → secret `DIST_CERT_PASSWORD`

Keep `dist.key`/`dist.p12` in a password manager and delete loose copies.
The certificate expires after a year; see "Certificate renewal" in SKILL.md.

## 3. (Nothing for Development)

Deliberately no development certificate, device registration, or
development profile for CI. Local Debug builds on a developer's own Mac use
Xcode's automatic signing as normal.

## 4. Bundle IDs (App IDs)

The **app's** bundle ID must exist before you can create the app record:

1. developer.apple.com → Certificates, Identifiers & Profiles →
   **Identifiers → +** → *App IDs* → *App*.
2. Description: the app name. **Explicit** bundle ID, exactly matching
   `PRODUCT_BUNDLE_IDENTIFIER` (e.g. `com.example.myapp`).
3. Capabilities: you can leave these unchecked — the ship workflow enables
   whatever is in `CAPABILITIES`. Checking them now is also fine.

**Extension** bundle IDs (`com.example.myapp.widgets`, …) don't need manual
registration: the workflow passes `BUNDLE_NAME` and the script registers
them. Register by hand if you prefer.

Capabilities that need extra configuration (App Groups, iCloud containers,
Associated Domains, Push) can't be fully set up by the script — it only
turns the capability on. Create the group/container IDs and assign them in
the portal, then re-run the workflow so it regenerates the profile.

## 5. App record in App Store Connect

Uploads are rejected if no app record exists for the bundle ID.

1. App Store Connect → **Apps → + → New App**.
2. Platform **iOS**; Name (the public App Store name — must be unique on
   the store; can change later); Primary language; **Bundle ID** — pick the
   one from §4; **SKU** — any internal string, e.g. the bundle ID;
   User Access — Full Access.
3. Nothing else is needed for TestFlight. Store listing, screenshots, pricing
   and privacy details are only required for App Store submission.

## 6. TestFlight

1. App Store Connect → your app → **TestFlight**.
2. **Internal Testing → +** → create a group (e.g. "Team"). Enable
   **automatic distribution** so every processed build goes to it.
3. Add testers. Internal testers must be users of your App Store Connect
   team (Users and Access → +, any role works; up to 100). They install the
   **TestFlight** app on iPhone and accept the email invite.
4. **Export compliance:** if Info.plist has
   `ITSAppUsesNonExemptEncryption = NO`, builds skip the question. Otherwise
   each build waits on "Missing Compliance" until someone answers it in the
   TestFlight tab.
5. **External testers** (people outside the team / public link) need a
   *Test Information* page (feedback email, description, privacy policy URL)
   and the first build of each version goes through **Beta App Review**
   (usually < 1 day).

After the first successful ship, a build takes 5–15 minutes to process,
then appears under the internal group. Builds expire after 90 days.
