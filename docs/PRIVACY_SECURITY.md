# Privacy & Security

This document describes Cénit's privacy posture, security model, and the hardening
applied to the parts of the codebase that touch untrusted input. It is written
against the actual source tree; file paths and identifiers below are real and can
be checked.

> **Not a medical device.** Cénit is an independent, local-first health app built
> on Apple Health: it reads **your own** biometric data from **your own** iPhone,
> on-device, with your HealthKit permission. It is not affiliated with, endorsed
> by, or connected to Apple Inc. All computed outputs (HRV, sleep, strain, SpO₂,
> skin temperature, respiratory rate) are approximations and are not clinically
> validated. See `DISCLAIMER.md` and `ATTRIBUTION.md` at the repo root.

---

## 1. Design principle: offline by default

Cénit is **offline by construction**. It is Apple Health-only: metrics are computed
on-device from HealthKit data plus optional file imports, and stored in a single local
SQLite file. There is no server, no account, no login, no cloud sync, and no telemetry
anywhere in the app.

There is exactly **one** opt-in network exception, off until you turn it on:
**exercise media download** (§1.1b). It fetches an instructional image/GIF for an
exercise from a fixed third-party CDN, only when you enable it and only for exercises
you view. Nothing else in the app ever touches the network, and your raw biometric
data never does. (The former BYO-key external AI Coach was removed.)

Data enters Cénit two ways:

| Path | Transport | Direction |
|------|-----------|-----------|
| Apple Health | HealthKit, on-device | Read-only from Health |
| File import | User-selected files on disk | Read-only from disk |

Earlier versions of Cénit could collect data from a fitness band over Bluetooth. That path
has been fully retired and removed: Cénit no longer pairs with, connects to, or reads from
any band, and the former protocol package no longer exists in the repo. Any band-sourced
rows collected by earlier versions remain in the local database as historical data — nothing
re-reads, re-validates, or adds to them, and, like everything else in the database, they
never leave the device.

The only outbound path is the opt-in exception above; the rest of the app,
including the entire biometric pipeline, produces no network traffic of any kind.

### 1.1 Network code: only the one opt-in feature

The biometric pipeline and the shipping packages
(`BiometricStreams`, `CenitStore`, `StrandAnalytics`, `StrandTraining`, `StrandImport`,
`StrandDesign`) contain **no** use of `URLSession`, `URLRequest`, `NWConnection`,
`dataTask`, or any other networking API. The **only** networking anywhere in the app is
exercise media download (`Cenit/Media/MediaDownloadCoordinator.swift`, §1.1b). The package
manifests reference dependency *download* URLs that Swift Package Manager resolves at build
time, never at runtime:

```
Packages/CenitStore/Package.swift   → https://github.com/groue/GRDB.swift.git
Packages/StrandImport/Package.swift → https://github.com/weichsel/ZIPFoundation.git
```

GRDB.swift is the SQLite layer; ZIPFoundation is the archive reader used by the
importers. Neither opens a socket.

### 1.1b Exercise media download (optional, off by default)

The exercise catalog can show an instructional image/GIF per exercise. Fetching it is
off by default and entirely optional:

- **Off until you enable it.** The toggle lives in Settings
  (`noop.exerciseMediaEnabled`, default `false`). With it off, `MediaDownloadCoordinator`
  never constructs a request — the zero-request guarantee is structural, not just a
  convention at the call sites.
- **What is sent.** Once enabled, viewing (or bulk-downloading) an exercise's media is a
  plain `GET` of that exercise's fixed image URL on the ExerciseDB CDN
  (`static.exercisedb.dev`), baked into the local catalog at build time — no runtime
  search, no API key, no account.
- **What is NOT sent.** No biometric data, no account or device identifiers, no query —
  just a request for a specific, pre-known static asset.
- **Cached locally.** Downloaded media is cached on-device
  (`Cenit/Media/MediaCache.swift`) so the same exercise is fetched at most once; disabling
  the toggle stops new downloads but does not delete what's cached (a separate
  "delete all cached media" action does).

If you never enable exercise media download, Cénit makes zero network connections.

### 1.2 The iOS app's entitlements

The iOS app ships with a deliberately minimal entitlement set
(`CenitApp/Resources/NOOP.entitlements`):

```xml
<key>com.apple.developer.healthkit</key>                       <true/>
<key>com.apple.security.application-groups</key>               <array>group.com.feriracheta.cenit</array>
```

- **`healthkit`** — read your own Apple Health data on-device (steps, heart rate, sleep)
  to compute metrics, and write back the metrics Cénit computes, only when you allow it.
  The Clinical/Verifiable Health Records key is intentionally **omitted** — Cénit never
  reads clinical records.
- **`application-groups`** — a shared container so the app and its widgets read the same
  tiny snapshot.

Notably **absent**: any **networking entitlement or code**. iOS does not gate outbound
network behind a sandbox entitlement the way the macOS App Sandbox did, so the offline
guarantee here is **structural in the code, not the OS**: the biometric pipeline and
shipping packages contain no networking API at all (§1.1), and the only code that can
ever open a socket is the opt-in exercise media downloader (§1.1b). The app also has no
broad-filesystem access: it reads only the import files you explicitly pick, plus its own
container.

This is the structural guarantee behind "offline by design": the privacy property holds
because there is no network code to begin with, not merely by convention.

---

## 2. Data at rest

### 2.1 Where the data lives

All durable data is stored in a single GRDB/SQLite database. The app
opens it at (`Cenit/Data/StorePaths.swift`):

```
<Application Support>/OpenWhoop/whoop.sqlite
```

On iOS every app is sandboxed by the OS, so `<Application Support>` resolves **inside
the app's private data container** (under the app's home directory), not in any
shared or user-global location. No other app can reach it through the filesystem.

The schema is defined by a versioned `DatabaseMigrator` in
`Packages/CenitStore/Sources/CenitStore/Database.swift` (currently schema version 9).
It holds exactly the kinds of data you would expect from the features:

- **Decoded biometric streams** (durable): `hrSample`, `rrInterval`, `spo2Sample`,
  `skinTempSample`, `respSample`, `gravitySample`, `battery`, `event`.
- **Derived/cached metrics**: `sleepSession`, `dailyMetric`, `workout`, `journal`,
  `appleDaily`, and the generic long-format `metricSeries`.
- **A transient raw outbox** (`rawBatch`): compressed raw BLE frames, **prunable**.
- **Device records** (`device`): device id (historical), MAC, name, first/last-seen timestamps.

The database is opened in WAL journal mode with `synchronous = NORMAL` and a busy
timeout, tuned for bulk import/backfill writes
(`Packages/CenitStore/Sources/CenitStore/CenitStore.swift`). WAL means you will also
see `whoop.sqlite-wal` and `whoop.sqlite-shm` sidecar files alongside the main
database — they live in the same container.

### 2.2 Encryption

The SQLite file is **not encrypted at rest by Cénit itself.** Confidentiality of the
data on disk relies on the platform:

- **iOS Data Protection** — iOS encrypts every file with hardware-backed keys tied to
  the device passcode. Cénit's database inherits the default protection class
  (`NSFileProtectionCompleteUntilFirstUserAuthentication`): the file is encrypted and
  unreadable until you first unlock the device after a reboot, after which the key
  stays available so the app can keep recording in the background. Setting a device
  passcode is what activates this — without one, the at-rest key isn't bound to a secret.
- The **app sandbox** keeps other apps from reading the file directly.

What this does **not** protect against: someone with your unlocked phone in hand (the
data is plaintext to the running app once the device is unlocked), or an unencrypted
backup of the container. Turn on **Encrypt iPhone Backup** (or rely on encrypted iCloud
backups) so the database isn't readable inside a backup.

> **Option: SQLCipher.** GRDB supports SQLCipher (an encrypted SQLite build) as a
> drop-in. Wiring Cénit's `DatabaseQueue` to a SQLCipher build with a
> Keychain-derived key would give at-rest encryption independent of the OS Data
> Protection class. This is not enabled in the current build, but the persistence
> layer is small and centralized (one `CenitStore.init(path:)`), so it is a
> contained change.

### 2.3 Data minimization & pruning

The raw-frame outbox (`rawBatch`) is treated as transient, not as the system of
record — the decoded streams are durable, the raw frames are a compressed,
**prunable** buffer. The prune policy in
`Packages/CenitStore/Sources/CenitStore/RawOutbox.swift` deletes old batches:

```sql
DELETE FROM rawBatch WHERE syncedAt IS NOT NULL AND syncedAt < ?
```

So raw captures do not accumulate forever. (The `syncedAt`/upload-related columns are
schema scaffolding inherited from the upstream collection library; in Cénit's offline
configuration nothing uploads, and the raw buffer is purely a local replay/recovery
aid.)

### 2.4 Diagnostics

There is no live strap connection log in the shipping app (band pairing was retired,
FER-1003). Diagnostics for HealthKit sync and imports stay on-device; nothing is
uploaded by Cénit.

### 2.5 Backups

Cénit's database can be backed up two ways, both entirely local to devices and storage
you already control — Cénit's own code never uploads a backup anywhere itself:

- **Manual export / import** (`Cenit/Data/DataBackup.swift`). Export checkpoints the WAL
  and copies the single `whoop.sqlite` file to a location you pick through the system
  document picker (Files, iCloud Drive, AirDrop, etc.). Import validates the chosen file
  (checks the SQLite magic header), snapshots your current database to a rollback
  sidecar first, then swaps the new file in atomically — a failure mid-import leaves the
  original database, including its WAL, fully intact.
- **Automatic backup** (`Cenit/Data/DataBackup.swift`, `AutoBackup`). Optional and off
  until you pick a destination folder (typically in your own iCloud Drive). Cénit
  remembers that folder via a **security-scoped bookmark** — the standard iOS mechanism
  for retaining permission to a user-picked location without a broader filesystem
  entitlement — and drops a fresh copy there roughly once a day, right after a sync.
  Turning it off stops future copies; it does not delete what's already there.

In both cases the destination is a folder the OS lets you pick; whether that folder
itself syncs off-device (e.g. because it's in iCloud Drive) is between you and Apple's
iCloud, outside anything Cénit does.

---

## 3. Threat model

Cénit parses **untrusted input** from files chosen for import (and HealthKit samples
from the OS). Imports are treated as hostile and validated before anything reaches the
database. Apple Health export files in particular can be very large (multi-hundred-MB to
multi-GB), so resource exhaustion is part of the model.

What is explicitly **out of scope**: Cénit cannot defend the data against an attacker
who already controls your unlocked user session (see §2.2).

### 3.1 Threat A: a malicious import file (zip bombs, XML bombs, huge exports)

The Apple Health importer lives in `Packages/StrandImport/` and assumes the file is hostile.

**Apple Health (`AppleHealthImporter.swift`).** Apple Health exports routinely exceed
1 GB, and a malicious one could be far worse.

- **Streaming SAX parse, never DOM.** The importer parses with `XMLParser` /
  `XMLParserDelegate` over an `InputStream` opened directly on the file. It explicitly
  does **not** use `XMLParser(contentsOf:)`, which would load the whole multi-hundred-
  MB document into memory first. Element handling runs inside a per-element
  `autoreleasepool` so temporaries from tens of millions of elements drain instead of
  accumulating — peak memory stays bounded regardless of file size.
- **Zip-bomb cap on decompression.** When the input is a `.zip`, `export.xml` is
  extracted to a temp file in fixed-size chunks with a running budget; the moment the
  decompressed total crosses the ceiling, extraction aborts:

  ```swift
  var written = 0
  let cap = 8 << 30   // 8 GB decompressed ceiling — zip-bomb guard
  _ = try archive.extract(entry, bufferSize: 1 << 20) { chunk in
      written += chunk.count
      if written > cap { throw ImportError.xmlParseFailed("export.xml too large") }
      try handle.write(contentsOf: chunk)
  }
  ```

  Chunks go straight to disk, so a bomb cannot inflate RAM. This deliberately replaced
  an earlier pipe-fed parser that could deadlock or crash on a malformed export.
- **Robust error handling.** Parse failures are surfaced as typed `ImportError`s; the
  delegate distinguishes a genuinely malformed document from a benign empty/EOF
  condition rather than crashing.
- **Temp files are cleaned up** via `defer { try? FileManager.default.removeItem(at: tmp) }`.

---

## 4. What Cénit does *not* collect or transmit

- **No accounts, no login.** Nothing to sign into; no credentials
  stored.
- **No telemetry / analytics / crash reporting.** No third-party SDKs of that kind.
- **No cloud, no sync, no remote backup.** Your data never leaves the machine via
  Cénit.
- **No advertising identifiers, no tracking.**
- **No WHOOP account or API credentials, and no live connection to a WHOOP strap.**
  Cénit is Apple Health-only; it does not authenticate against, or pull from, any WHOOP
  server, and no longer opens a Bluetooth connection to a strap at all.

---

## 5. Hardening summary

| Surface | Risk | Mitigation | Where |
|---------|------|------------|-------|
| Process | Data exfiltration / network egress | Only one opt-in feature networks: exercise media download (a GET to a fixed CDN, only when enabled — §1.1b); nothing else makes a network call | `Cenit/Media/MediaDownloadCoordinator.swift` |
| Filesystem | Broad disk access | iOS app sandbox; imports read only the files you pick via the document picker; data stays in the app's private container | `CenitApp/Resources/NOOP.entitlements`, `Cenit/Data/StorePaths.swift` |
| App state | Implausible-but-valid values | Range gates (e.g. HR 30–220) at HealthKit / import boundaries | `HealthKitBridge`, import glue |
| Health import | XML bomb / multi-GB DOM blowup | Streaming SAX over `InputStream`; per-element autorelease pool | `StrandImport/AppleHealthImporter.swift` |
| Health import | Zip bomb | 8 GB decompressed ceiling, chunked to disk, hard abort | `StrandImport/AppleHealthImporter.swift` |
| Data at rest | Device theft / offline access | Relies on iOS Data Protection (passcode-tied) + app sandbox; SQLCipher available as an option | `CenitStore/CenitStore.swift` |

---

## 6. Reporting a security issue

Cénit is a hobbyist, non-commercial interoperability and research project provided
**as-is, with no warranty**, for personal and educational use only (see
`DISCLAIMER.md`). If you find a security or privacy issue, please open a GitHub issue
describing the problem and a reproduction; sensitive reports can be coordinated
privately via the contact on the project's GitHub profile. Issues will be reviewed in
good faith.

---

## 7. Credits

- **`groue/GRDB.swift`** — the SQLite persistence layer.
- **`weichsel/ZIPFoundation`** — the archive reader used by the importers.

See `ATTRIBUTION.md` and `DISCLAIMER.md` for the full attribution and good-faith
notice. Cénit contains no WHOOP proprietary code, firmware, binaries, logos, or
assets, and performs no DRM circumvention.
