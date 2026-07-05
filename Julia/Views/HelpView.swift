import SwiftUI

/// The keymap, tig-style: every binding and search trick in one page.
/// Global rows read the user's actual configured hotkeys.
struct HelpView: View {
    private var sections: [(title: String, entries: [(keys: String, action: String)])] {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sections, id: \.title) { section in
                    Text(section.title)
                        .font(Design.sectionHeaderFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(section.entries, id: \.keys) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(entry.keys)
                                .font(.system(size: 14, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(.primary)
                                .frame(width: 190, alignment: .leading)
                            Text(entry.action)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

#Preview {
    HelpView()
        .frame(width: 480, height: 500)
        .background(.thickMaterial)
}
