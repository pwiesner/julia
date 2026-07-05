import SwiftUI

/// One column of the keymap page: sections of key/action rows. The page
/// splits by whole section so each stays intact — the eye scans down a
/// column, never across one.
struct HelpColumnView: View {
    let sections: [(title: String, entries: [(keys: String, action: String)])]

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
