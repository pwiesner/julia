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

                    Image(systemName: session.isAttached ? "terminal.fill" : "terminal")
                        .font(.system(size: 12, weight: session.isAttached ? .semibold : .regular))
                        .foregroundStyle(session.isAttached ? Color(red: 0.639, green: 0.745, blue: 0.549) : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.name)
                            .font(Design.sidebarTitleFont)

                        if let lastAttached = session.lastAttached {
                            Text(lastAttached, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                .font(Design.sidebarDetailFont)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Text("^[\(session.windows.count) window](inflect: true)")
                        .font(Design.sidebarDetailFont)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sessionHelp)

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

    private var sessionHelp: String {
        if let created = session.created {
            "Created \(created.formatted(.relative(presentation: .named)))"
        } else {
            session.name
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 28, alignment: .trailing)

                Image(systemName: window.agentGlyph ?? "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(window.agentGlyphColor ?? (window.isActive ? .blue : .secondary))
                    .accessibilityLabel(window.agentStatusText.map { "Claude: \($0)" } ?? "")

                Text(window.displayName)
                    .font(Design.sidebarRowFont)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if window.isActive {
                    Image(systemName: "asterisk")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }

                Spacer()

                // The sidebar is a slim map: process, branch, and agent
                // state live in the actions column. Just name and recency.
                if let lastActivity = window.lastActivity {
                    Text(lastActivity, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(Design.sidebarDetailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 3)
            .padding(.leading, 32)
            .padding(.trailing, 6)
            .opacity(window.isStale ? 0.55 : 1)
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
                    TmuxWindow(id: "@0", index: 0, name: "nvim", sessionName: "dev", isActive: true, currentPath: "/Users/me/projects/julia", currentCommand: "nvim"),
                    TmuxWindow(id: "@1", index: 1, name: "shell", sessionName: "dev", currentPath: "/Users/me/projects/julia", currentCommand: "zsh"),
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
