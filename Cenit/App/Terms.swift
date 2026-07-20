import Foundation

/// The Terms of Use the first-run gate presents. Bump `currentVersion` when the terms MATERIALLY
/// change (risk / liability / medical / affiliation wording) to re-prompt every user for a fresh
/// acknowledgment; leave it for typo fixes. Mirrored on Android by `NoopPrefs.TERMS_VERSION`. The
/// full text lives in `TERMS.md`, shipped with Cénit.
enum Terms {
    static let currentVersion = "2.0"

    /// The load-bearing points the user must accept on first launch — the plain-English summary of
    /// `TERMS.md` §1–§6. Kept identical to the Android `Terms.points`. Each is (headline, body).
    static let points: [(String, String)] = [
        ("Reads your data from Apple Health, on your device",
         "Cénit reads your health and fitness data directly from Apple Health, on your iPhone — no separate hardware pairing required."),
        ("Offline and local — no account, no server",
         "Every metric is processed and stored only on your device. There is no Cénit server, no Cénit account, and no telemetry — the maintainers cannot see your data and never receive it."),
        ("General wellness only — not a medical device",
         "Cénit is not a medical device and provides no medical advice. Every metric is an unvalidated approximation — don't use Cénit to diagnose, treat, or make any health decision. Always consult a qualified professional."),
        ("No warranty; liability limited",
         "Cénit is free and provided \"as is\", with no warranty. Liability is limited to the maximum extent the law that applies to you allows, and nothing here removes protections your local law won't let us remove."),
    ]
}
