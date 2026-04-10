import SwiftTerm
import SwiftUI

/// Renders a captured tmux pane into colored text using SwiftTerm as a
/// headless parser. We never instantiate SwiftTerm's view — we feed bytes
/// to a `Terminal` configured at the captured pane's exact dimensions, then
/// walk its public buffer cell-by-cell to build a SwiftUI AttributedString.
struct TerminalPreviewView: View {
    let capture: TmuxService.PaneCapture

    private static let fontSize: CGFloat = 8

    /// Pre-computed cell width for the preview font, used to give the Text
    /// view an explicit pixel width that's wide enough to never wrap. This
    /// is the only reliable way I've found to keep SwiftUI Text from
    /// wrapping inside a ScrollView for multi-line content.
    private static let cellWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let glyph = font.glyph(withName: "W")
        return font.advancement(forGlyph: glyph).width
    }()

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(rendered)
                .font(.system(size: Self.fontSize, design: .monospaced))
                .lineSpacing(0)
                .textSelection(.enabled)
                .frame(width: CGFloat(capture.cols) * Self.cellWidth, alignment: .leading)
                .padding(8)
        }
        .defaultScrollAnchor(.bottomLeading)
        .background(Color.black)
    }

    private var rendered: AttributedString {
        TerminalRenderer.render(capture)
    }
}

private enum TerminalRenderer {
    static func render(_ capture: TmuxService.PaneCapture) -> AttributedString {
        var options = TerminalOptions.default
        options.cols = capture.cols
        options.rows = capture.rows
        options.scrollback = 0
        // The captured content from `tmux capture-pane` is line-oriented with
        // LF-only line endings. Without convertEol, SwiftTerm treats LF as
        // "move down without resetting column", so consecutive lines smear
        // sideways. Treating LF as CR+LF makes each captured line start
        // cleanly at col 0.
        options.convertEol = true

        let terminal = Terminal(delegate: NoopTerminalDelegate(), options: options)
        terminal.feed(text: capture.content)

        var result = AttributedString()
        for row in 0..<capture.rows {
            for col in 0..<capture.cols {
                let cell = terminal.buffer.getChar(atBufferRelative: Position(col: col, row: row))
                let char = cell.getCharacter()
                if char == "\0" || char == "\u{0}" { continue }

                var run = AttributedString(String(char))
                run.foregroundColor = swiftUIColor(from: cell.attribute.fg, isBackground: false)
                if case .defaultInvertedColor = cell.attribute.bg {
                    // Default background — don't paint, let the view's bg show through.
                } else {
                    run.backgroundColor = swiftUIColor(from: cell.attribute.bg, isBackground: true)
                }
                result.append(run)
            }
            result.append(AttributedString("\n"))
        }
        return result
    }

    private static func swiftUIColor(from color: Attribute.Color, isBackground: Bool) -> SwiftUI.Color {
        switch color {
        case .defaultColor:
            return isBackground ? .black : .white
        case .defaultInvertedColor:
            return isBackground ? .white : .black
        case .trueColor(let r, let g, let b):
            return SwiftUI.Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        case .ansi256(let code):
            return ansi256(code)
        }
    }

    /// Standard xterm 256-color palette mapping.
    /// 0–15: ANSI base colors. 16–231: 6×6×6 RGB cube. 232–255: 24-step grayscale.
    private static func ansi256(_ code: UInt8) -> SwiftUI.Color {
        if code < 16 {
            let table: [(Double, Double, Double)] = [
                (0, 0, 0), (0.67, 0, 0), (0, 0.67, 0), (0.67, 0.33, 0),
                (0, 0, 0.67), (0.67, 0, 0.67), (0, 0.67, 0.67), (0.78, 0.78, 0.78),
                (0.33, 0.33, 0.33), (1, 0.33, 0.33), (0.33, 1, 0.33), (1, 1, 0.33),
                (0.33, 0.33, 1), (1, 0.33, 1), (0.33, 1, 1), (1, 1, 1),
            ]
            let (r, g, b) = table[Int(code)]
            return SwiftUI.Color(red: r, green: g, blue: b)
        }
        if code < 232 {
            let n = Int(code) - 16
            let r = (n / 36) % 6
            let g = (n / 6) % 6
            let b = n % 6
            let toLevel: (Int) -> Double = { i in i == 0 ? 0 : Double(55 + 40 * i) / 255.0 }
            return SwiftUI.Color(red: toLevel(r), green: toLevel(g), blue: toLevel(b))
        }
        let level = Double(8 + 10 * (Int(code) - 232)) / 255.0
        return SwiftUI.Color(red: level, green: level, blue: level)
    }
}

/// A no-op terminal delegate so we can run a headless `Terminal` for parsing.
/// All methods on `TerminalDelegate` other than `send` have defaults; `send`
/// is the one we have to provide explicitly.
private final class NoopTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
