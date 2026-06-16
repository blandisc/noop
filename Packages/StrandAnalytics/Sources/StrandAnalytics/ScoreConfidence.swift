import Foundation

// ScoreConfidence.swift — per-result certainty tier.
//
// A small, dependency-free 3-tier ladder a descriptive engine can ride so a thin
// result reads truthfully instead of faking precision. Ordered lowest → highest:
//
//   .calibrating — not enough input to compute at all (the number, if any, is a placeholder).
//   .building    — usable but thin: enough to compute, but the sample is small / provisional.
//   .solid       — full inputs present and the result is trusted.
//
// Minimal port from upstream NoopApp/noop: only the tiers are brought over. The
// upstream's Charge / Effort / Rest derivation helpers depend on scoring types this
// fork doesn't have yet, so they are intentionally omitted here (see FER-123); add
// them alongside that scoring system if/when it lands.
public enum ScoreConfidence: String, Equatable, Sendable, Codable {
    case calibrating
    case building
    case solid
}
