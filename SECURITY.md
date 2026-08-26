# Security Policy

## Scope

Cénit is a fully offline, on-device app. It has no servers, no accounts, and no
cloud sync, so the usual web attack surface does not apply. It reads Apple Health
on your device and no longer pairs with any Bluetooth hardware (the WHOOP-band /
BLE path was retired). What remains is local:

- **Local SQLite database** — every reading is stored on your own device.
- **File imports** — the Apple Health export ZIP, and Cénit backup files, that you
  choose to open.
- **AI Coach (optional, off by default)** — the only feature that makes a network
  request, and only with an API key you supply yourself, to the provider you choose.

A useful security report is one that lets data leave the device when it shouldn't,
lets a crafted import file corrupt the database or run code, or otherwise breaks the
offline, local-only guarantee the app makes.

## Reporting a vulnerability

Cénit is maintained anonymously and has no security contact email. **Report
security issues by opening a GitHub issue** on the repository.

If a public report would put users at immediate risk before a fix can ship,
open an issue with a short, non-exploitable summary (what is affected and how
severe) and hold the proof-of-concept details until a fix is released.

Please include, as far as you can without putting anyone at risk:

- A description of the issue and the guarantee it breaks
- Steps to reproduce
- The potential impact
- A suggested fix, if you have one

Because there is no staffed inbox, response times depend on maintainer
availability — there is no guaranteed SLA. Confirmed issues are prioritised for
the next release.

## Supported versions

Only the latest release receives fixes. Cénit ships from source; if you build your
own copy, rebuild from the latest tag to pick up security fixes.

## Out of scope

- Vulnerabilities that require physical access to an already-unlocked device
- Issues in third-party dependencies — please report those upstream (see
  [`NOTICE`](NOTICE) for the bundled libraries and their licences)
- The user's own API key being misused after they have entered it (the key is
  stored in the platform keystore; protecting the device account is the user's job)
