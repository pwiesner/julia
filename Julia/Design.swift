import SwiftUI

/// Shared design constants so the palette reads as one surface instead of
/// a collection of ad-hoc font sizes and paddings.
enum Design {
    // MARK: Chrome

    static let windowCornerRadius: Double = 18
    static let rowCornerRadius: Double = 9
    static let chipCornerRadius: Double = 6.5
    static let previewCornerRadius: Double = 10

    /// Hairline rim that catches light at the top of the panel, fading out
    /// toward the bottom — reads as depth on any wallpaper.
    static var panelRim: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.28), .white.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Type scale

    static let searchFont = Font.system(size: 17)
    static let rowTitleFont = Font.system(size: 13, weight: .medium)
    static let rowSubtitleFont = Font.system(size: 11)
    static let sectionHeaderFont = Font.system(size: 10, weight: .semibold)
    static let shortcutHintFont = Font.system(size: 10, design: .monospaced)
    static let sidebarTitleFont = Font.system(size: 12, weight: .medium)
    static let sidebarRowFont = Font.system(size: 11)
    static let sidebarDetailFont = Font.system(size: 9)

    // MARK: Metrics

    static let iconChipSize: Double = 26
    static let rowVerticalPadding: Double = 7
    static let rowHorizontalPadding: Double = 10
}
