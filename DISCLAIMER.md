# Disclaimer, Trademark & Good-Faith Notice

## 1. Independent & unofficial

This is an independent, unofficial, non-commercial project by an individual hobbyist. Cénit is
**not affiliated with, endorsed by, sponsored by, or connected to Apple Inc.** in any way. All
references to "Apple Health" and "HealthKit" describe the on-device Apple framework this software
reads data from, and are **nominative fair use** of those marks — used only to identify that
framework, never to imply origin, sponsorship, or endorsement, and never as the name of this
project's own product or brand.

"Apple", "Apple Health", "HealthKit", and any related marks are the property of Apple Inc. All
other trademarks belong to their respective owners.

**Cénit only reads data already present in your own Apple Health, with your permission, and only
on your own device.** This software does not encourage or require you to violate any terms you have
agreed to; how you use your own health data is your responsibility.

## 2. No proprietary material is contained or redistributed

This repository contains **only original work** authored by the project's contributors. Cénit
reads data exclusively through **Apple's public HealthKit API**, with the user's explicit
permission, granted through the standard iOS permission dialog. No reverse engineering,
decompilation, or examination of any proprietary application, framework, or protocol is performed
or required to build or run Cénit. Specifically, this repository does **NOT** contain, bundle,
mirror, or link to any of the following:

- Apple system frameworks, binaries, or extracted framework code;
- decompiled, disassembled, or reverse-compiled Apple source code;
- Apple logos, icons, artwork, fonts, screenshots, or other copyrighted/branded assets;
- any Apple account credentials, API secrets, or server endpoints.

Application icons, color choices, and UI in this project are **original creations**. Any
similarity to a generic "health app" aesthetic is coincidental and not copied from any protected
work.

## 3. Nature of the work: an offline Apple Health companion

The purpose of this project is to let a person read **their own health and fitness data**,
already present in **their own Apple Health**, entirely on **their own device**.

- It operates only with the **user's own device** and the **user's own data**, accessed through
  Apple's public, documented HealthKit API.
- It does **not** circumvent any technological protection measure, and does not bypass any
  subscription, paywall, login, or account control.
- Nothing here is intended to compete with, devalue, or harm Apple's products, services, or
  business.

The app is offline by construction, with exactly two narrow, opt-in, off-by-default exceptions:
a bring-your-own-key AI Coach, and an exercise media downloader (FER-722) that, only if the user
turns it on, fetches exercise thumbnails/loops from a third-party service (ExerciseDB) and caches
them on-device. Neither exception sends any Apple Health data, biometric data, or user identifier
anywhere — see [`README.md`](README.md#privacy) for exactly what each one shares.

## 4. Licensing, non-commercial use, and no warranty

Cénit's own source code and documentation are made available under the **PolyForm Noncommercial
License 1.0.0** (see [`LICENSE`](LICENSE)): free for personal and other **non-commercial** use —
you may read, run, fork, and contribute, but commercial use is not granted. The license covers
Cénit's original work only; bundled dependencies keep their own licenses (see [`NOTICE`](NOTICE)).

The software is provided **as-is**, with **no warranty of any kind**, express or implied. You use it
entirely **at your own risk**, including any risk to your device, data, or warranty status. The
authors accept no liability for any damage, loss, or consequence arising from its use. Review your
own agreements and local laws before use; you are responsible for your own compliance.

## 5. Not a medical device

Outputs such as heart rate, HRV, recovery, strain, sleep stages, SpO₂, respiratory rate, and skin
temperature are **approximations** computed from published methods. They are **not** clinically
validated, are **not** a medical device, and are **not** medical advice. Do not use them to
diagnose, treat, or make health decisions. Consult a qualified professional.

## 6. Good-faith takedown contact

This project is shared in good faith and the author wants to respect others' rights. If you are
a rights holder and believe anything in this repository infringes your rights, **please contact
the author directly via a GitHub issue or the email on the author's GitHub profile before filing a
formal complaint.** The author will review promptly and, where a concern is well-founded, will
cooperate — including editing or removing the material in question.

The author's intent is to build an honest, offline Apple Health companion, not to infringe
anyone's rights; most concerns can be resolved quickly and amicably through direct contact.
