# GitHub setup

Needs repo **Admin**. All in the repo's **Settings** tab.

## 1. The `testflight` environment

Settings → **Environments → New environment** → name it `testflight`
(must match `environment: testflight` in `ship-testflight.yml`).

- **Deployment branches and tags** → *Selected branches and tags* → add
  `main`. Now only a run from `main` can read the secrets below, so editing
  the workflow on a feature branch can't exfiltrate them.
- Optional: **Required reviewers** if shipping should need a second person's
  click. Leave off for a solo project.
- **Environment secrets** → add all five:

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID (e.g. `2X9R4HXF34`) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID (a UUID) |
| `APP_STORE_CONNECT_API_KEY_P8` | full `.p8` text, BEGIN/END lines included |
| `DIST_CERT_P12_BASE64` | one-line base64 of the `.p12` |
| `DIST_CERT_PASSWORD` | the `.p12` export password |

Put them on the **environment**, not under Actions → Repository secrets.
(Repository secrets would also work, but would be readable from any branch.)

With the `gh` CLI, if the user prefers (run on their machine, never paste
secret values into chat):

```bash
gh api -X PUT repos/OWNER/REPO/environments/testflight \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/OWNER/REPO/environments/testflight/deployment-branch-policies -f name=main
gh secret set APP_STORE_CONNECT_API_KEY_ID --env testflight
gh secret set APP_STORE_CONNECT_ISSUER_ID  --env testflight
gh secret set APP_STORE_CONNECT_API_KEY_P8 --env testflight < AuthKey_XXXX.p8
gh secret set DIST_CERT_PASSWORD           --env testflight
base64 -i dist.p12 | tr -d '\n' | gh secret set DIST_CERT_P12_BASE64 --env testflight
```

## 2. Protect `main`

Settings → **Rules → Rulesets → New branch ruleset** (or classic Branches →
Branch protection rule):

- Target: default branch.
- **Require a pull request before merging.** Required approvals: 0 for a
  solo project (the loop is "CI green → merge it yourself"); raise it for a team.
- **Require status checks to pass** → add **`test`** (the job id in
  `ci.yml`). It only appears in the picker after CI has run once, so open
  the first PR before setting this.
- **Block force pushes.**

Because `ci.yml` has no `paths-ignore`, the check always reports, so
doc-only PRs aren't stuck waiting on it.

## 3. Runners and cost

- `runs-on: macos-26` is a GitHub-hosted Apple-silicon image. If the job
  sits on "Waiting for a runner", the label may have changed — check
  GitHub's runner-images list and update both workflows.
- Public repos: free. Private repos: macOS minutes count against the plan
  at a multiple of the Linux rate. A CI run is ~5–8 min; a ship ~15–20.
  `concurrency: cancel-in-progress` keeps superseded PR pushes from
  burning minutes.

## 4. Shipping

Actions tab → **Ship TestFlight** → **Run workflow** → branch `main` →
Run. Any other branch fails at the environment gate by design.
