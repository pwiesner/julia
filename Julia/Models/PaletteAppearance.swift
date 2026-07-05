import AppKit
import SwiftUI

/// User-selectable appearance for julia's windows — the palette and the
/// settings page — independent of the system theme. Defaults to dark:
/// the palette floats over terminals, and terminals live in the dark.
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

    /// The same choice for SwiftUI-managed windows; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    // MARK: - Persistence

    static let defaultsKey = "paletteAppearance"

    static var saved: PaletteAppearance {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(PaletteAppearance.init) ?? .dark
    }
}
