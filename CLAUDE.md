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

**Deep reference:** before any structural change (new package, DB migration, BLE/protocol path, concurrency model, cross-package work), read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the full system map (pipeline, package boundaries, actor model, live vs. historical path, safe-trim, storage schema). It's the source of truth so you don't have to re-derive the design from code. Keep it honest: **if your change moves the architecture, update `docs/ARCHITECTURE.md` in the same PR** (same discipline as the CHANGELOG). The `/arquitecto` step owns this doc.

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

## Working principles (how to make changes)

Bias toward caution over speed; for trivial changes, use judgment.

- **Think before coding.** State your assumptions. If a requirement has multiple readings or something is unclear, stop and surface it rather than picking silently — for product work, that means bouncing it back to `/pm`. Don't hide confusion.
- **Simplicity first.** Write the minimum that solves the stated problem. No speculative features, no abstractions for single-use code, no configurability nobody asked for, no error handling for impossible cases. If 200 lines could be 50, rewrite it.
- **Surgical changes.** Touch only what the task requires. Don't "improve" adjacent code, reformat, or refactor what isn't broken; match the existing style even if you'd do it differently. Remove only the orphans *your* change created; if you spot unrelated dead code, mention it — don't delete it. Every changed line should trace to the request.
- **Goal-driven execution.** Turn the task into verifiable checks — the issue's acceptance criteria — and loop until they pass before delivering. Weak success criteria ("make it work") are a signal to go back to `/pm`, not to guess.

## How we work here (process)

The flow is **requirement → (architecture) → experience → screen → code → QA**, with acceptance criteria as the through-line. Five skills cover it (the two design ones only kick in for screen work; the architecture one only for structural/deep changes):

- **`/pm`** turns a raw idea into a clear requirement (acceptance criteria + Definition of Done) and files it as a Linear issue — *before* any code. Start product work here. For screen work it runs the **UX** pass to fix the flow, states, copy (es-MX) and accessibility into the requirement.
- **`/arquitecto`** (standalone, selective — *not* every change) is the **technical-design** step between `/pm` and `/implement`, for **cambios de fondo only**: a new package, a DB migration, the BLE/protocol path, the concurrency model, or anything cross-package. It reads [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), proposes the *how* (where the code lands per "where logic belongs", which migrations/tests, the invariants it must preserve), validates it against the hard rules, and writes verifiable technical criteria `/implement` then checks. `/pm` owns the *what*; `/arquitecto` owns the *how* and keeps `docs/ARCHITECTURE.md` fresh. Skip it for UI/copy/bugfix/single-screen work.
- **`/ux`** (folded into `/pm`, also standalone) designs the **experience** before pixels: flow, states (incl. no-HealthKit-permission and offline), information architecture, copy and accessibility — never colors/fonts. Leans on `lazyweb` + `impeccable`.
- **`/ui`** (folded into `/implement` as the pre-code step, also standalone) designs the **visual** against `StrandDesign`: token-by-token mapping plus a **rendered PNG per state (ImageRenderer)** the user approves *before* any code. Leans on `design-for-ai` + `lazyweb` + `impeccable`.
- **`/implement FER-NN`** takes that issue to production: runs the UI pass (PNG gate) for screen work, implements against the criteria, verifies each one (QA), and — if all pass and the build is green — merges to `iOS` and closes the issue. It stops to ask only if QA fails, it cannot verify, the change is high-risk, or the user did not approve the PNG.

`/ux`, `/ui`, and `/arquitecto` also exist as subagents (`.claude/agents/`) so `/implement` can delegate the design or technical-design pass, or explore variants in parallel.

- **Linear:** team **Fer**, project **NOOP iOS**. Label every issue by type (`UI/Today`, `Analytics`, `Bug`, `Import`, `Performance`, `i18n`, `Diseño`, `Feature`, …). Issue lifecycle: **Todo → In Progress → In Review → Done**. Reference the issue in the PR (`Closes FER-NN`).
- **Branch hygiene — one branch per issue, never collide.** Use the issue's Linear-generated `gitBranchName` (e.g. `blandisc/fer-81-…`), branched from an up-to-date `origin/iOS` (`git fetch` first). Never work on `iOS`, never reuse another issue's branch, and if the branch already exists, another session owns it — stop, don't overwrite. PRs target `iOS`, squash-merge, then delete the branch.
- **Finish the job, then clean up.** When QA passes, take the work all the way: merge, close the issue at Done, delete the branch, leave the tree clean — no half-done branches or stray open PRs. **Then sync the canonical build checkout** so the next iPhone build isn't stale: `git -C ~/code/noop fetch origin && git -C ~/code/noop merge --ff-only origin/iOS` (`--ff-only` preserves any uncommitted work there; if it can't fast-forward, tell the user instead of forcing). "Production" means merged to `origin/iOS` **and** pulled into `~/code/noop` — that's where the iPhone build comes from. The one manual step left to the user: building/installing on the iPhone from Xcode.
- **Always document.** Descriptive commits + a CHANGELOG entry for user-facing changes.
- **Worktrees:** sessions run in a per-branch git worktree. Read/edit/build under the worktree path, never the main checkout. Build/run the real app from the canonical `~/code/noop` checkout (a worktree copy installs a stale bundle).
- **`.claude/` is gitignored** (line 84): local settings stay out of git; to version a skill, `git add -f` just that file — don't edit `.gitignore` (it tracks upstream).
