import AppKit

/// User-selectable appearance for the palette panel, independent of the
/// system theme. Defaults to dark — the palette floats over terminals,
/// and terminals live in the dark.
enum PaletteAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil means follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Persistence

    static let defaultsKey = "paletteAppearance"

    static var saved: PaletteAppearance {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(PaletteAppearance.init) ?? .dark
    }
}
