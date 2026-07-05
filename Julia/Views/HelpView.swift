import SwiftUI

/// The keymap, tig-style: every binding and search trick in one page.
/// Global rows read the user's actual configured hotkeys. Two columns so
/// the whole keymap fits without scrolling — a cheat sheet below the
/// fold is a worse cheat sheet.
struct HelpView: View {
    /// Navigation: the bindings that move you around.
    private var leftSections: [(title: String, entries: [(keys: String, action: String)])] {
        [
            ("Anywhere", [
                (Hotkey.savedPalette.displayString, "toggle the palette"),
                (Hotkey.savedJumpToAgent.displayString, "jump to the longest-waiting agent (press again for the next)")
            ]),
            ("Palette", [
                ("type", "search windows, sessions, branches, commands"),
                ("↑ ↓ ↵", "select and switch"),
                ("⌘1–9", "activate row 1–9"),
                ("⇥", "flip between windows and agents"),
                ("⌘B", "toggle the sessions sidebar"),
                ("⌘P", "open the selected branch's pull request"),
                ("⌘⇧W", "wrap up the selected agent gracefully"),
                ("⌘/", "this page"),
                ("esc", "close")
            ])
        ]
    }

    /// Maintenance and search: what you do once you're somewhere.
    private var rightSections: [(title: String, entries: [(keys: String, action: String)])] {
        [
            ("Screens — double-tap ⇧", [
                ("⇧⇧ w", "windows — home"),
                ("⇧⇧ a", "agents overview"),
                ("⇧⇧ t", "tidy"),
                ("⇧⇧ /", "this page"),
                ("type it", "\"windows\", \"agents\", \"tidy\", \"help\" too")
            ]),
            ("Tidy — type \"tidy\"", [
                ("⌘⇧W", "wrap up the selected idle agent"),
                ("⌘K", "kill the selected window (tidy only)"),
                ("esc", "back to windows")
            ]),
            ("Search tricks", [
                ("<session>:", "drill into one session's windows"),
                ("new <name>", "create a session"),
                ("kill <name>", "kill a session"),
                ("rename <a> to <b>", "rename a session"),
                ("move <session>", "move the current window"),
                ("window", "new window in the current session")
            ])
        ]
    }

    var body: some View {
        // The scroll view stays as a safety net for cramped layouts; at
        // the palette's normal size everything fits without it.
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                HelpColumnView(sections: leftSections)
                HelpColumnView(sections: rightSections)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

#Preview {
    HelpView()
        .frame(width: 1060, height: 500)
        .background(.thickMaterial)
}
