# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Cénit is a fully **offline, on-device** health companion built on **Apple Health**: it syncs HealthKit into local SQLite and computes recovery / strain / HRV / sleep on-device. No server, no account, no network by default. Not affiliated with WHOOP; not a medical device (see [DISCLAIMER.md](DISCLAIMER.md)).

**[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) is the full guide** — repository layout, build/test, the design-system rules, and how to add a metric / screen / DB migration. Read it before any non-trivial change. This file is the high-signal summary, not a replacement.

## Architecture (the big picture)

Cross-platform **Swift packages do the real work**; thin platform apps wrap them.

- `Packages/BiometricStreams` — the neutral vocabulary of decoded rows (`HRSample`, `RRInterval`, `StreamEvent`, `Streams`, `ParsedValue`). **Root of the graph: zero deps, Foundation-only.** `CenitStore` and `StrandAnalytics` depend on it, **never the reverse**; no `@_exported import`.
- `Packages/CenitStore` — GRDB/SQLite persistence (versioned migrations).
- `Packages/StrandAnalytics` — recovery / strain / HRV / sleep math. **Pure, database-free.**
- `Packages/StrandTraining` — strength domain: exercise catalog, types/rules (sets/reps, progression, routines). **Pure, Foundation-only** (no GRDB/UI).
- `Packages/StrandImport` — Apple Health importer.
- `Packages/StrandDesign` — the SwiftUI design system (single source of visual truth).
- `Cenit/` — the **SwiftUI app layer** (`App`, `Data`, `LiveActivity`, `Media`, `Onboarding`, `Screens`, `System`). HealthKit lives in `CenitApp/Health`.
- `Cenit*/` — the iOS app shell + widgets/tests (`CenitApp`, `CenitShared`, `CenitWidgets`, `CenitUnitTests`, `CenitUITests`). The app target/module/product is `Cenit`; it builds `Cenit/`.

**Rule of thumb:** the more wire-level or math-level a change is, the deeper into `Packages/` it belongs, and the more it must be covered by a `swift test` that needs no app or HealthKit hardware. Every package targets both iOS and macOS and **must not** `import AppKit/UIKit/CoreBluetooth` — guard framework code with `#if canImport(...)`. See the "where logic belongs" table in CONTRIBUTING.

**Deep reference:** before any structural change (new package, DB migration, concurrency model, cross-package work), read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the full system map (pipeline, package boundaries, actor model, live vs. historical path, storage schema). It's the source of truth so you don't have to re-derive the design from code. Keep it honest: **if your change moves the architecture, update `docs/ARCHITECTURE.md` in the same PR** (same discipline as the CHANGELOG). The `/arquitecto` step owns this doc.

## Build & test

**`Tools/verify.sh` is the one verification command — run it before finishing any change that touches Swift.** Modes: no args = auto (linters + build/test of touched packages + app `build-for-testing` if the app layer changed), `quick` (linters only), `package <N>`, `app`, `app-tests` (runs `CenitUnitTests` on a simulator, signed — an unsigned build compiles but cannot RUN: without the App Group entitlement the app aborts before the first test, which is how the suite rotted unseen until FER-49. CI now runs it too, nightly / on `ci-app`, so this is the local mirror of that gate, not the only place it happens). It encapsulates the whole resource choreography below (wait-for-idle, `-jobs 4`, DerivedData prune, simulator shutdown) so you don't have to. A Stop-hook blocks ending the turn with unverified `.swift` edits; live-iteration sessions (`/canvas`, `/inject`) opt out by creating `.claude/live-session` (delete it when the session ends — the user is the eye there).

Packages are the fast loop (no Xcode, no strap):

```bash
cd Packages/<Name> && swift build && swift test
swift test --filter <TestCaseOrMethod>      # run a single test
```

iOS app (the Xcode project is generated from `project.yml`, never committed):

```bash
xcodegen generate                           # after adding/removing files or editing project.yml
xcodebuild -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -jobs 4 build
xcodebuild -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS' -jobs 4 test
```

**Always pass `-jobs 4`** on full app builds. The dev Mac has 16 GB / 8 cores; an uncapped `xcodebuild` fans `swift-frontend` across all 8 cores, and parallel worktree sessions building at once exhaust RAM ("system has run out of application memory"). The fast loop (`swift build`/`swift test` on `Packages/**`) doesn't hit this — prefer it whenever the change doesn't touch the app layer.

**One build at a time — never build while another build is running.** Two concurrent full builds (your `xcodebuild` + the user's Xcode GUI, or two agent sessions) is the #1 recurring cause of the machine-wide OOM, and `-jobs` caps do NOT make it survivable. Before any full app build, wait until the machine is idle: `while pgrep -q swift-frontend; do sleep 30; done` — then build. If `swift-frontend` keeps running for many minutes, the user is likely building from the Xcode GUI: keep waiting, don't race them.

**Build hygiene:** every worktree build mints its own ~1 GB DerivedData folder (`Cenit-<hash>`) that outlives the worktree — they accumulate into tens of GB and the disk pressure slows every build on this Mac. Before a full app build, run `Tools/prune-deriveddata.sh` (deletes only folders whose checkout no longer exists; safe with Xcode open). **When you finish an issue, run `Tools/cleanup.sh --apply`** — it prunes delivered worktrees *and* the DerivedData they left behind, in one command (run it without `--apply` for a dry run). Do not hand-roll this check with `git merge-base --is-ancestor`: everything here is squash-merged, which makes that test blind to every delivered branch (FER-194). When your session ends, leave no `.build/` or generated `Cenit.xcodeproj` behind in a worktree that's done. If you ran anything on the iOS Simulator (`xcodebuild test` with a Simulator destination, `simctl boot/launch`), shut it down when you're done: `xcrun simctl shutdown all` — a booted simulator keeps running headless (~8 GB of RAM) indefinitely, even with Simulator.app closed, and starves the next Xcode build into an OOM.

CI has **six workflows**: `swift-packages` (package build/test on `Packages/**` changes), `ios-app` (full app compile **+ `CenitUnitTests` on a simulator**, FER-50: **nightly over `iOS`**, plus on any PR carrying the `ci-app` label — **the label is MANDATORY on heavy-lane PRs** that touch `Cenit/**`/`CenitApp/**`; light-lane PRs may rely on the nightly), `design-lint`, `design-tokens`, `i18n-guard`, and `release`. (If `swift`/`xcodebuild` fail while fetching SwiftPM dependencies, a local `GIT_CONFIG` override is the known workaround.)

## Rules that will get a change rejected

- **Offline only.** No server, telemetry, account, or network call — ever. (One opt-in exception already exists and stays **off by default** behind an explicit toggle: exercise-media download in `Cenit/Media/`. The app default is zero network. Do **not** weaken this rule for new code.)
- **The design system is law.** Screens use only `StrandDesign` tokens (`StrandPalette`, `StrandFont`, `CenitMetrics`) and components (`NoopCard`, `StatTile`, …). No raw hex, font sizes, spacing, or one-off cards. If a token is missing, add it to `StrandDesign` (with a `#Preview`) — don't inline it. The **DNA** that gives those tokens a point of view lives in [docs/design-system/DESIGN.md](docs/design-system/DESIGN.md): **«Liquid Glass · El Eje»** (tinted glass on a white canvas, two regimes — mosaico / sobrio; see also [LIQUID-GLASS.md](docs/design-system/LIQUID-GLASS.md)) is **canonical** for new/redesigned screens. «Instrumento diurno / papel cálido» is the previous generation (absorbed, in migration — `DESIGN.md` §8). The dark system is **legacy** (maintain, don't extend; Watch OLED is the only live exception). For iOS-native decisions (HIG, SF Symbols, motion) cite Apple via the **Cupertino** MCP, not guesswork.
- **Transparent math.** Analytics are documented approximations — add a test and cite the method (Task Force 1996, Karvonen, Edwards/Banister, Tanaka). No black boxes, no clinical claims.
- **Migrations are append-only.** Never edit a shipped GRDB migration; add `vN+1` plus a `MigrationTests` case. Every `ADD COLUMN` goes through `CenitStore.addColumnIfMissing` (in `Database.swift`), not a raw `db.alter`/`add` — it guards on the live schema so a migration that re-runs against a DB that already grew the column (common after iterating a migration locally and reinstalling over the same on-device DB) is a no-op, not a "duplicate column" crash that wedges startup (FER-791/792).
- **Don't commit generated/local files** (`Cenit.xcodeproj/`, build output, secrets/keystores). One concern per PR.

## Working principles (how to make changes)

Bias toward caution over speed; for trivial changes, use judgment.

- **Think before coding.** State your assumptions. If a requirement has multiple readings or something is unclear, stop and surface it rather than picking silently — for product work, that means bouncing it back to `/pm`. Don't hide confusion.
- **Simplicity first.** Write the minimum that solves the stated problem. No speculative features, no abstractions for single-use code, no configurability nobody asked for, no error handling for impossible cases. If 200 lines could be 50, rewrite it.
- **Surgical changes.** Touch only what the task requires. Don't "improve" adjacent code, reformat, or refactor what isn't broken; match the existing style even if you'd do it differently. Remove only the orphans *your* change created; if you spot unrelated dead code, mention it — don't delete it. Every changed line should trace to the request.
- **Goal-driven execution.** Turn the task into verifiable checks — the issue's acceptance criteria — and loop until they pass before delivering. Weak success criteria ("make it work") are a signal to go back to `/pm`, not to guess.
- **Read before writing.** Before coding, produce a 5-line inventory of what already exists and will be reused (components, helpers, engines). Writing *your* version of something the app already has is the single most expensive defect class we've measured (FER-119: 15 defects from exactly this). No inventory, no code.
- **Kill the class, not the instance.** When a review surfaces 3+ defects of the same type, stop hunting them one by one: write a gate/lint/test that catches the whole class (like the i18n gate in FER-123), run one sweep, and move on.

## How we work here (process)

The flow is **requirement → (architecture) → experience → screen → code → QA**, with acceptance criteria as the through-line. Six skills cover it (the two design ones only kick in for screen work; the architecture one only for structural/deep changes). **How much of the flow runs depends on the change's risk — see "Two risk lanes" below.** The skills:

- **`/pm`** turns a raw idea into a clear requirement (acceptance criteria + Definition of Done) and files it as a **Multica** issue — *before* any code. Start product work here. For screen work it runs the **UX** pass to fix the flow, states, copy (es-MX) and accessibility into the requirement.
- **`/arquitecto`** (standalone, selective — *not* every change) is the **technical-design** step between `/pm` and `/implement`, for **cambios de fondo only**: a new package, a DB migration, the concurrency model, or anything cross-package. It reads [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), proposes the *how* (where the code lands per "where logic belongs", which migrations/tests, the invariants it must preserve), validates it against the hard rules, and writes verifiable technical criteria `/implement` then checks. `/pm` owns the *what*; `/arquitecto` owns the *how* and keeps `docs/ARCHITECTURE.md` fresh. Skip it for UI/copy/bugfix/single-screen work.
- **`/ux`** (folded into `/pm`, also standalone) designs the **experience** before pixels, anchored to the **Liquid Glass · El Eje** DNA: flow, states (incl. no-HealthKit-permission and offline), information architecture, copy and iOS-real accessibility (Dynamic Type/VoiceOver) — never colors/fonts. Leans on `lazyweb` (real flows + brainstorm) + `impeccable`.
- **`/ui`** (folded into `/implement` as the pre-code step, also standalone) designs the **visual** against the DNA ([docs/design-system/DESIGN.md](docs/design-system/DESIGN.md) «Liquid Glass · El Eje») and `StrandDesign`: token-by-token mapping, an **AI Slop Test gate** (anti-generic) and iOS-native authority (HIG/SF Symbols/motion via **Cupertino**), then an **HTML preview per state (`show_widget`, faithful to Liquid Glass · El Eje)** the user approves *before* any code — HTML, not PNG, because that's what the user can actually see. `design-for-ai`/`impeccable` are used for *theory and anti-slop only — translated to SwiftUI, never CSS*. Leans on `design-for-ai` + `impeccable` + `lazyweb` (evidence + best-practices router) + `Cupertino`.
- **`/implement FER-NN`** takes that issue to production: runs the UI pass (HTML-preview gate) for screen work, implements against the criteria, runs its own fast QA loop, and merges to `iOS`. On the **heavy lane** it first hands the branch to the **independent verifier as the merge gate** (PASS + green build required) and then runs a `/simplify` pass; on the **light lane** its own QA is the gate. It stops to ask only if QA fails after the bounded loop, it cannot verify, the change is high-risk, or the user did not approve the preview.
- **`/qa FER-NN`** (folded into `/implement` as the pre-merge gate on the **heavy lane**, also standalone) is the **independent verifier** — the agent that built the change is *not* the one that signs off on it. It takes the branch + the issue's acceptance criteria (never the implementer's narrative), re-runs build/tests itself, probes states and edge cases adversarially, and returns a **per-criterion verdict (PASS / FAIL / BLOCKED)** with reproducible evidence. It reports defects; it never edits code. Bounded to 3 rounds before escalating to the user.

`/ux`, `/ui`, `/arquitecto`, and `/qa` also exist as subagents (`.claude/agents/`) so `/implement` can delegate the experience, visual, technical-design and verification passes (or explore variants in parallel) without taking over the main conversation.

**Two risk lanes (how much process runs).** Not every change earns the same ceremony — running the full gate on a margin tweak costs more than the rework it prevents. `/pm` tags each issue with a **`Carril`** field, and `/implement`/`/ui`/`/ux`/`/qa` read it (design work runs the same two lanes — heavy = full evidence + variants + AI Slop Test; light = map to existing tokens within the DNA + one preview):
- **Light** — reversible, cosmetic (UI/copy/layout/i18n, a small tweak to an existing screen). `/pm` writes it lean (no UX subagent); `/implement` does its own build + criteria check + HTML preview and ships — **no independent `/qa`, no 3-round loop, no `/arquitecto`**. Rework is trivial and you verify on the iPhone, so the independent gate would cost more than it protects.
- **Heavy** — risky or hard to revert (DB migration, analytics/math, on-device data, cross-package/concurrency, or a feature with real logic). Full flow: `/arquitecto` if structural, the independent `/qa` gate, then a `/simplify` pass (agents tend to over-build). **When in doubt, heavy.**

**Review-round budget (hard cap, 2026-08-25).** Adversarial review rounds are capped: **2 rounds on the light lane, 3 on the heavy lane**. Whatever survives the cap becomes a backlog issue — it is not chased in round 8. Sole exception that breaks the cap: defects that corrupt data or copy that lies about the body. Rationale: the late rounds on «Hoy» (8 rounds, 105 findings) caught cosmetics, and 1 in 4 late fixes opened a new defect.

**Batches, not drips.** Micro-tweaks to the same screen (a nudge, a rename, a copy fix) are grouped into **one polish-session issue** — one umbrella issue, one branch, one review, one merge. Ten tweaks pay one toll, not ten. A standalone issue per 26-pt nudge is the anti-pattern.

**Live-by-default for visual tweaks.** When the owner is present, light-lane UI/copy work starts directly in `/inject` or `/canvas` — the owner's live eye *is* the approval. The async HTML-preview gate is for new screens/redesigns or when the owner is away.

**Proportional verification.** Per-tweak verification on the light lane is `swift build`/`swift test` of the touched package. The full app build (+ simulator) runs **once at batch close**, not per tweak.

**Orchestrated runs (`/orquesta`) are the default for any multi-step job** (an epic, a multi-issue batch — anything beyond a single tweak). Model split, fixed by the owner (2026-08-25, amended 2026-08-27): **Fable/Opus orchestrates** (specs, decisions, heavy lane), **Sonnet implements** the light lane (parallel worktree subagents), **DeepSeek** takes purely mechanical batches, **Grok** reviews adversarially AND implements well-specified batches via `grok-lane.sh` only (owner reversal 2026-08-27 — see DECISIONS.md; never reviews its own diff, never compiles: the director verifies). `grok-lane.sh` is multi-engine (`--engine grok|deepseek|glm`); **GLM** (Z.ai `glm-5.3-flash` vía OpenRouter, key en `$OPENROUTER_API_KEY`) is an **experimental** cheap lane added 2026-08-27, not yet part of the owner-blessed split — same isolation contract, same report. Waves are planned so parallel work lives in `Packages/**`; the full app build runs once per wave. **The `/tablero` dashboard is mandatory on every orchestrated run** — raised at kickoff, updated at every issue close and wave boundary; a run whose board is stale forfeits its autonomy (the owner can't audit what they can't see).

- **Multica (no Linear):** workspace **Fer**, project **Cénit iOS**. CLI: `multica` (already authenticated). Label every issue by type (`UI/Today`, `Analytics`, `Bug`, `Import`, `Performance`, `i18n`, `Diseño`, `Feature`, …). Issue lifecycle: **todo → in_progress → in_review → done** (also `backlog` / `blocked` / `cancelled`). Reference the issue in the PR (`Closes FER-NN`) so Multica can link and auto-close on merge. Common commands: `multica issue list|get|create|update|status|comment add|label add`, `multica issue search "…"`. Prefer Multica over any Linear MCP/plugin.
- **Branch hygiene — one branch per issue, never collide.** Name branches from the Multica identifier + short slug (e.g. `fer-81-empty-today-state`), branched from an up-to-date `origin/iOS` (`git fetch` first). Never work on `iOS`, never reuse another issue's branch, and if the branch already exists, another session owns it — stop, don't overwrite. PRs target `iOS`, squash-merge, then delete the branch.
- **Owner decisions are recorded in [docs/DECISIONS.md](docs/DECISIONS.md)** — read it before proposing anything that touches a settled topic, and append every new owner decision there in the same PR that implements it. Decisions are reversible, but only explicitly — never by silently re-opening them.
- **No orphaned WIP.** A session that ends leaves its Multica issues either advanced or back in `todo` with a note of where things stand — never parked in `in_progress`/`in_review` with no active owner. A stale `in_progress` is a traffic light that lies.
- **Finish the job, then clean up.** When QA passes, take the work all the way: merge, **close the issue at Done in the same step you delete the branch** (not as a later chore — three issues sat green-but-stale for up to 26 days because it was), delete the branch, run `Tools/cleanup.sh --apply`, leave the tree clean — no half-done branches or stray open PRs. **Then sync the canonical build checkout** so the next iPhone build isn't stale: `git -C ~/code/noop fetch origin && git -C ~/code/noop merge --ff-only origin/iOS` (`--ff-only` preserves any uncommitted work there; if it can't fast-forward, tell the user instead of forcing). "Production" means merged to `origin/iOS` **and** pulled into `~/code/noop` — that's where the iPhone build comes from. The one manual step left to the user: building/installing on the iPhone from Xcode.
- **Always document.** Descriptive commits + a CHANGELOG entry for user-facing changes.
- **Worktrees:** sessions run in a per-branch git worktree. Read/edit/build under the worktree path, never the main checkout. Build/run the real app from the canonical `~/code/noop` checkout (a worktree copy installs a stale bundle).
- **`.claude/` is gitignored** (line 84): local settings stay out of git; to version a skill, `git add -f` just that file — don't edit `.gitignore` (it tracks upstream).
