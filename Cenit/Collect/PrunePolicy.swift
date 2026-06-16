import Foundation
/// Raw-outbox retention (raw is transient on the phone; the server is the durable archive).
/// Pruning never loses a decoded metric — decoded is persisted first (E2 invariant).
enum PrunePolicy {
    static let keepWindowSeconds = 24 * 3600        // keep synced raw browsable ~24h
    static let maxUnsyncedBytes = 50 * 1024 * 1024  // drop oldest un-synced beyond ~50MB
}
