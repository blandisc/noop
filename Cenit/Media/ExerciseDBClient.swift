import Foundation

// MARK: - ExerciseDB client (the second networked feature — strictly opt-in · FER-722)
//
// NOOP is offline by design. Alongside AI Coach (`Cenit/AI/AICoach.swift`), this is the only other
// place that ever makes a network call, and it is gated the same way: nothing happens unless the
// user turns on "Descargar biblioteca de ejercicios" in Ajustes (default off) — see
// `MediaDownloadCoordinator`, which is the single point that reads that flag before ever
// constructing this client. `init?` also fails closed on its own: without a configured API key
// (`Cenit/Secrets.xcconfig`, gitignored), the client can't even be built, so a fork with no key
// never sends a request even if the toggle is on.

/// The exercise media this app cares about from an ExerciseDB v2 lookup. EDB v2 exposes one URL
/// (`gifUrl`) that serves as both the still thumbnail and the looping clip — if a future version
/// splits those into distinct fields, add a second property here instead of duplicating this one.
struct EDBExerciseMedia: Decodable, Sendable {
    let mediaURL: URL?
}

/// Thin client for ExerciseDB v2 (RapidAPI). Looks up media by free-text exercise name — see
/// `MediaDownloadCoordinator` for why there's no static catalog→EDB-id mapping.
struct ExerciseDBClient {
    private let apiKey: String
    private let host: String
    private let session: URLSession

    /// Fails to construct without a configured key — the fail-closed half of the "toggle off ⇒ zero
    /// requests" guarantee (the other half is `MediaDownloadCoordinator` never calling this at all).
    init?(session: URLSession = .shared) {
        let key = Bundle.main.object(forInfoDictionaryKey: "EDBApiKey") as? String
        self.init(apiKey: key, session: session)
    }

    /// Testable entry point: same fail-closed rule, but the key is passed in directly instead of
    /// read from `Bundle.main` — so a test can assert the empty/missing case deterministically,
    /// regardless of whatever key (if any) is configured in the local build.
    init?(apiKey: String?, session: URLSession = .shared) {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.apiKey = apiKey
        self.host = "exercisedb.p.rapidapi.com"
        self.session = session
    }

    /// Search by exercise name (English, normalized) and return the first match's media, or nil if
    /// nothing matched. Network errors propagate to the caller, which treats any failure as "no
    /// media available right now" and falls back to the YouTube hand-off row.
    func lookup(name: String) async throws -> EDBExerciseMedia? {
        guard let url = Self.lookupURL(forName: name, host: host) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(host, forHTTPHeaderField: "x-rapidapi-host")

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let results = try JSONDecoder().decode([EDBExerciseEntry].self, from: data)
        guard let first = results.first else { return nil }
        return EDBExerciseMedia(mediaURL: first.gifUrl.flatMap(URL.init(string:)))
    }

    /// Raw wire shape from EDB v2.
    private struct EDBExerciseEntry: Decodable {
        let gifUrl: String?
    }

    /// Builds the search URL for a free-text exercise name — split out (and `internal`, not
    /// `private`) so a test can pin the encoding without any network. `URLComponents.path` treats
    /// "/" as a path separator, which would silently truncate real catalog names like "3/4 Sit-Up"
    /// at the first slash; this percent-encodes the whole name as one opaque path segment instead,
    /// explicitly escaping "/" (and "?"/"#", which `.urlPathAllowed` otherwise lets through
    /// unescaped inside a segment).
    static func lookupURL(forName name: String, host: String) -> URL? {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var allowedInSegment = CharacterSet.urlPathAllowed
        allowedInSegment.remove(charactersIn: "/?#")
        guard let encodedName = normalized.addingPercentEncoding(withAllowedCharacters: allowedInSegment) else {
            return nil
        }
        return URL(string: "https://\(host)/exercises/name/\(encodedName)")
    }
}
