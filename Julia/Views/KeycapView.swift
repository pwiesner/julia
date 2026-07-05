import SwiftUI

/// A chord rendered as a keycap chip. The cap's shape anchors the eye,
/// so a column of them scans like keys, not text; the slightly heavier
/// bottom edge is what makes it read "key" rather than "tag".
struct KeycapView: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.09))
                    .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

#Preview {
    VStack(spacing: 8) {
        KeycapView(keys: "⌘⇧W")
        KeycapView(keys: "rename <a> to <b>")
    }
    .padding()
    .background(.thickMaterial)
}
