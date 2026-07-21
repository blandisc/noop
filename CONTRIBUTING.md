# Contributing to Cénit

Thanks for your interest in contributing. Cénit is a standalone, fully **offline**
health app on **Apple Health** — it syncs HealthKit into on-device SQLite and
computes recovery / strain / HRV / sleep locally. No servers, no accounts, no
data leaving the device — with exactly one narrow, opt-in, off-by-default
exception: the exercise media downloader (thumbnails/loops cached from
ExerciseDB, FER-722). Documented in [`README.md`](README.md#privacy). WHOOP band
support was retired (FER-1003); historical imports are preserved.

This file is a quick orientation. The **full contributing guide** —
repository layout, the design-system rules, how to add a metric / screen /
migration, and the commit conventions — lives in
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). Read that before opening a
non-trivial PR.

> Cénit is not affiliated with, endorsed by, or connected to WHOOP, Inc., and is
> not a medical device. See [`DISCLAIMER.md`](DISCLAIMER.md).

---

## Quick start

The codebase is reusable Swift packages (`Packages/`) plus a thin iOS app layer
(`Cenit/`, built by the `Cenit` target). The fastest feedback loop is the
packages — they build and test on their own, no Xcode project needed.

### Swift packages

```bash
# Test just the package you touched (substitute the name):
cd Packages/StrandAnalytics && swift build && swift test
```

The seven packages are `BiometricStreams` (neutral biometric row vocabulary),
`WhoopProtocol` (BLE framing / decode — research only, not linked to the app),
`CenitStore` (SQLite persistence), `StrandAnalytics` (recovery / strain / HRV /
sleep math), `StrandTraining` (strength domain), `StrandImport` (WHOOP CSV +
Apple Health importers), and `StrandDesign` (the SwiftUI design system).

### iOS app

The Xcode project is generated from `project.yml` and is **not** committed.

```bash
brew install xcodegen
xcodegen generate         # regenerate after any project.yml or file add/remove
```

Then open the project in Xcode, select the `Cenit` scheme, and run on your
iPhone. For the full build guide (signing, installing on-device without a paid
Apple ID), see [`docs/BUILD.md`](docs/BUILD.md).

---

## What CI checks

The **Swift Packages CI** workflow runs on every PR and push to `main` that
touches `Packages/**`. It compiles and runs unit tests only — no code signing, no
secrets, no release.

| Workflow | Trigger | What it does |
|---|---|---|
| **Swift Packages CI** (`.github/workflows/swift-packages.yml`) | changes under `Packages/**` | `swift build` + `swift test` for each package |

If CI fails on your PR, fix the cause rather than working around it. Never commit
generated output (`Cenit.xcodeproj/`) or any secrets, keystores, or `local.properties`.

---

## Submitting a PR

1. One concern per PR where practical (keep protocol, schema, and UI changes
   separate).
2. Fill in the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
3. For anything on the BLE path, state what you tested **on real hardware** and on
   which strap. A green build is not proof a command behaves correctly.
4. For analytics changes, add a test and cite the method.
5. For UI changes, use `StrandDesign` tokens only — no hardcoded colors, fonts,
   or spacing.

By opening a pull request you agree your contribution is licensed under the same
terms as the project — see [`LICENSE`](LICENSE).

---

## Reporting issues

- **Bugs and feature requests:** open an issue using the templates in
  [`.github/ISSUE_TEMPLATE`](.github/ISSUE_TEMPLATE). Cénit is on-device, so please
  leave out anything that identifies you.
- **Security issues:** see [`SECURITY.md`](SECURITY.md).

## Code of conduct

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md). Be respectful and
keep discussion focused on the technical work.
