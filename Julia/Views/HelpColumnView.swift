import SwiftUI

/// One column of the keymap page: sections of key/action rows. The page
/// splits by whole section so each stays intact — the eye scans down a
/// column, never across one.
struct HelpColumnView: View {
    let sections: [(title: String, entries: [(keys: String, action: String)])]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections, id: \.title) { section in
                // Each section is a card: the container edge glues the
                // header to its rows, so no cap alignment can strand a
                // header over emptiness. Inside, a Grid per section lets
                // the cap column hug that section's widest cap — chords
                // sit snug to their descriptions while a long-capped
                // section ("rename <a> to <b>") widens only itself.
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title)
                        .font(Design.sectionHeaderFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                        ForEach(section.entries, id: \.keys) { entry in
                            GridRow {
                                KeycapView(keys: entry.keys)
                                    .gridColumnAlignment(.trailing)
                                Text(entry.action)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.primary.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 8)
    }
}

#Preview {
    HelpColumnView(sections: [
        ("Example", [
            ("⌘P", "open the selected branch's pull request"),
            ("esc", "close")
        ])
    ])
    .frame(width: 520, height: 300)
    .background(.thickMaterial)
}
