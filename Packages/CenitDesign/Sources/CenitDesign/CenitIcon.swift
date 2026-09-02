import SwiftUI

/// Named icons — reference by PURPOSE, not by SF Symbol shape (see docs LENGUAJE.md / ICONOGRAFIA.md).
/// Covers the high-frequency + semantic set; one-off symbols may still be used inline.
public enum CenitIcon: String {
    // navigation / chrome
    case disclosure = "chevron.right"
    case back       = "chevron.left"
    case close      = "xmark"
    case confirm    = "checkmark"
    case add        = "plus"
    case more       = "ellipsis"
    case info       = "info.circle"
    case warning    = "exclamationmark.triangle.fill"
    case search     = "magnifyingglass"
    case up         = "arrow.up"
    case down       = "chevron.down"
    // domain / health
    case heart      = "heart.fill"
    case sleep      = "moon.zzz"
    case flame      = "flame"
    case experiment = "flask"
    case clock      = "clock"
    case calendar   = "calendar"

    public var systemName: String { rawValue }
    public var image: Image { Image(systemName: rawValue) }
}

#Preview("Icons") {
    let all: [CenitIcon] = [.disclosure, .back, .close, .confirm, .add, .more, .info, .warning, .search, .up, .down, .heart, .sleep, .flame, .experiment, .clock, .calendar]
    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
        ForEach(all, id: \.rawValue) { icon in
            VStack(spacing: 6) {
                icon.image.font(.title3)
                Text(icon.rawValue).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }.padding()
}
