# Contributing

You don't need a Mac. GitHub's macOS runners do all the building, testing,
and signing.

## The loop

1. Branch off `main`, edit, push.
2. Open a pull request. **CI** builds the app and runs all five test suites
   (a few minutes). Its log is your compiler: read errors there.
3. Once CI is green and the PR is approved, merge to `main`.

`main` is protected: changes land only through a PR with a passing CI check
and an approving review.

## Shipping to TestFlight

Actions tab → **Ship TestFlight** → Run workflow, on `main`. It signs,
uploads, and the build appears in TestFlight 5–15 minutes later. It can only
run from `main`; the signing secrets live on the `testflight` environment and
aren't available to other branches.

## Editing on Windows

Any editor works. VS Code with the Swift extension gives syntax highlighting
and basic completion. The app code won't compile locally on Windows (it uses
SwiftUI and other Apple frameworks), so rely on CI to check it.

Read `CLAUDE.md` for the code style this project follows.
