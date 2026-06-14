# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NOOP is a fully **offline, on-device** companion app for WHOOP straps (4.0 / 5.0 / MG): it pairs over BLE, stores everything locally in SQLite, and computes recovery / strain / HRV / sleep on-device. No server, no account, no network. Not affiliated with WHOOP; not a medical device (see [DISCLAIMER.md](DISCLAIMER.md)).

**[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) is the full guide** — repository layout, build/test, the design-system rules, the BLE safety contract, and how to add a metric / screen / BLE command / DB migration. Read it before any non-trivial change. This file is the high-signal summary, not a replacement.

## Architecture (the big picture)

Cross-platform **Swift packages do the real work**; thin platform apps wrap them.

- `Packages/WhoopProtocol` — BLE frame parsing, CRC, packet/event decode. **Pure, no CoreBluetooth** (runs in tests / CLI / Linux).
- `Packages/WhoopStore` — GRDB/SQLite persistence (versioned migrations).
- `Packages/StrandAnalytics` — recovery / strain / HRV / sleep math. **Pure, database-free.**
- `Packages/StrandImport` — WHOOP CSV + Apple Health importers.
- `Packages/StrandDesign` — the SwiftUI design system (single source of visual truth).
- `Strand/` — macOS app (the **reference implementation**); CoreBluetooth lives only here (`Strand/BLE`, `Strand/Collect`).
- `StrandiOS*/` — experimental iOS app target + widgets. `android/` — full shipped Kotlin app.

**Rule of thumb:** the more wire-level or math-level a change is, the deeper into `Packages/` it belongs, and the more it must be covered by a `swift test` that needs no app, strap, or CoreBluetooth. Every package targets both iOS and macOS and **must not** `import AppKit/UIKit/CoreBluetooth` — guard framework code with `#if canImport(...)`. See the "where logic belongs" table in CONTRIBUTING.

## Build & test

Packages are the fast loop (no Xcode, no strap):

```bash
cd Packages/<Name> && swift build && swift test
swift test --filter <TestCaseOrMethod>      # run a single test
```

macOS app (the Xcode project is generated from `project.yml`, never committed):

```bash
xcodegen generate                           # after adding/removing files or editing project.yml
xcodebuild -project Strand.xcodeproj -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Strand.xcodeproj -scheme Strand -destination 'platform=macOS' test
```

Android:

```bash
cd android && ./gradlew assembleFullDebug          # real app (JDK 17)
./gradlew testFullDebugUnitTest                     # unit tests
./gradlew assembleDemoDebug                         # 120 days of synthetic data, no strap
```

CI runs `swift build`/`swift test` only on `Packages/**` changes, and the Android unit tests only on `android/**` changes. (If `swift`/`xcodebuild` fail while fetching SwiftPM dependencies, a local `GIT_CONFIG` override is the known workaround.)

## Rules that will get a change rejected

- **Offline only.** No server, telemetry, account, or network call — ever.
- **No destructive BLE commands.** The `WhoopCommand` set in `Strand/BLE/Commands.swift` is a curated, reversible subset. Never add reboot / firmware-DFU / ship-mode / wipe / fuel-gauge-reset. CRC-gate every frame and reject `crcOK == false`. Anything that changes outbound bytes must be **verified on real hardware** and noted in the PR.
- **The design system is law.** Screens use only `StrandDesign` tokens (`StrandPalette`, `StrandFont`, `NoopMetrics`) and components (`NoopCard`, `StatTile`, …). No raw hex, font sizes, spacing, or one-off cards. If a token is missing, add it to `StrandDesign` (with a `#Preview`) — don't inline it.
- **Transparent math.** Analytics are documented approximations — add a test and cite the method (Task Force 1996, Karvonen, Edwards/Banister, Tanaka). No black boxes, no clinical claims.
- **Migrations are append-only.** Never edit a shipped GRDB migration; add `vN+1` plus a `MigrationTests` case.
- **Don't commit generated/local files** (`Strand.xcodeproj/`, build output, secrets/keystores). One concern per PR.

## How we work here (process)

- **Start product work with `/pm`.** It turns a raw idea into a clear requirement (with acceptance criteria) and files it as a Linear issue — *before* any code. Implement against those acceptance criteria and verify each one before opening the PR.
- **Linear:** team **Fer**, project **NOOP iOS**. Label every issue by type (`UI/Today`, `Analytics`, `Bug`, `Import`, `Performance`, `i18n`, `Diseño`, `Feature`, …). When you take an issue move it to **In Progress**, comment progress, and close it at **Done**. Reference it in the PR (`Closes FER-NN` where it applies).
- **PRs:** branch → PR **into `iOS`** → squash-merge. Descriptive commits + CHANGELOG entry; document the change (project convention: always document).
- **Worktrees:** sessions run in a per-branch git worktree. **Read/edit/build under the worktree path**, never the main checkout. Build/run the real app from the canonical `~/code/noop` checkout (a worktree copy installs a stale bundle).
- **`.claude/` is gitignored** (line 84): local settings stay out of git; to version a skill, `git add -f` just that file — don't edit `.gitignore` (it tracks upstream).
