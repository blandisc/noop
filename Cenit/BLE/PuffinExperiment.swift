import Foundation

/// Opt-in switch for the EXPERIMENTAL WHOOP 5.0/MG ("puffin") protocol probes.
///
/// Live HR on a 5/MG strap already works over the standard profile after CLIENT_HELLO. These probes
/// go further — sending puffin-framed commands (e.g. asking the strap to start its realtime stream)
/// to learn what a real 5/MG strap responds to. They are guesses, so they are OFF by default and only
/// ever written to the puffin command characteristic (fd4b0002). A 5/MG owner can flip this on under
/// Settings → Experimental to help map the protocol; everyone else is unaffected.
enum PuffinExperiment {
    /// Shared with the Settings toggle via `@AppStorage(PuffinExperiment.defaultsKey)`.
    static let defaultsKey = "noopPuffinExperiments"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}
