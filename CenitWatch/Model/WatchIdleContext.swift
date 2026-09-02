import CenitDesign

/// The resting-face context the iPhone resolves and pushes over `updateApplicationContext` (FER-96),
/// OUTSIDE any active session: today's routine name and the SAME daily verdict word/tone/advice
/// `EntrenarView.hiloDelVeredicto` already shows on the iPhone. `WatchWorkoutManager` adopts it from
/// `WorkoutMirrorMessage.idleContext`. All-nil (the default) until the first push, or after a fresh
/// pairing before the iPhone has pushed anything yet — the idle face then falls to its existing
/// «sin lectura» look, never a guessed word or color.
struct WatchIdleContext: Equatable {
    var word: String?
    var advice: String?
    var routineName: String?
    /// The wire form of the verdict's tone — one of `"clear"/"caution"/"ease"/"hollow"`, or nil.
    /// `CenitShared` carries this as a plain `String` (not `EntrenarHilo.Tone`) so it stays free of
    /// `CenitDesign` (Alcance §4 of FER-96) — see `tone` below for the one translation point.
    var toneRaw: String?

    /// `toneRaw` → `EntrenarHilo.Tone` — the ONE place the wrist turns the wire string back into the
    /// real enum. Any unrecognized or missing value falls to `.hollow` (the existing «sin lectura» aro
    /// punteado) — never a crash, never a guessed tone.
    var tone: EntrenarHilo.Tone {
        switch toneRaw {
        case "clear":   return .clear
        case "caution": return .caution
        case "ease":    return .ease
        default:        return .hollow
        }
    }
}
