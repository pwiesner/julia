import SwiftUI

struct SessionListView: View {
    let sessions: [TmuxSession]
    let onSelectSession: (String) -> Void
    let onSelectWindow: (String, Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(sessions) { session in
                    SessionRowView(
                        session: session,
                        onSelectSession: onSelectSession,
                        onSelectWindow: onSelectWindow
                    )
                }
            }
            .padding(8)
        }
    }
}

struct SessionRowView: View {
    let session: TmuxSession
    let onSelectSession: (String) -> Void
    let onSelectWindow: (String, Int) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                onSelectSession(session.name)
            } label: {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "terminal")
                        .font(.system(size: 12))
                        .foregroundStyle(session.isAttached ? .green : .secondary)

                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))

                    if session.isAttached {
                        Text("attached")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .clipShape(.rect(cornerRadius: 3))
                    }

                    Spacer()

                    Text("^[\(session.windows.count) window](inflect: true)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(session.windows) { window in
                    WindowRowView(
                        window: window,
                        onSelect: { onSelectWindow(session.name, window.index) }
                    )
                }
            }
        }
    }
}

struct WindowRowView: View {
    let window: TmuxWindow
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text("\(window.index):")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, alignment: .trailing)

                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(window.isActive ? .blue : .secondary)

                Text(window.name)
                    .font(.system(size: 11))

                if window.isActive {
                    Image(systemName: "asterisk")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.leading, 32)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SessionListView(
        sessions: [
            TmuxSession(
                id: "$0",
                name: "dev",
                windows: [
                    TmuxWindow(id: "@0", index: 0, name: "nvim", sessionName: "dev", isActive: true),
                    TmuxWindow(id: "@1", index: 1, name: "shell", sessionName: "dev"),
                    TmuxWindow(id: "@2", index: 2, name: "logs", sessionName: "dev")
                ],
                isAttached: true
            ),
            TmuxSession(
                id: "$1",
                name: "work",
                windows: [
                    TmuxWindow(id: "@3", index: 0, name: "main", sessionName: "work", isActive: true),
                    TmuxWindow(id: "@4", index: 1, name: "tests", sessionName: "work")
                ]
            )
        ],
        onSelectSession: { _ in },
        onSelectWindow: { _, _ in }
    )
    .frame(width: 250, height: 300)
    .background(.regularMaterial)
}
