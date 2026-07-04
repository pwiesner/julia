import SwiftUI

struct PaletteView: View {
    @Bindable var viewModel: PaletteViewModel
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool
    @AppStorage("isSidebarVisible") private var isSidebarVisible = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            HStack(spacing: 0) {
                contentArea
                Divider()
                previewPane
            }
        }
        .frame(width: 1100, height: 620)
        .background { quickJumpShortcuts }
        .background(.thickMaterial)
        .clipShape(.rect(cornerRadius: Design.windowCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Design.windowCornerRadius)
                .strokeBorder(Design.panelRim, lineWidth: 1)
        }
        .onAppear {
            viewModel.mode = .browsing
            viewModel.browseList = .windows
            viewModel.searchText = ""
            viewModel.selectedIndex = 0
            viewModel.previewContent = nil
            isSearchFocused = true
            viewModel.refresh()
        }
        .task {
            // Focus requested in onAppear can race the panel becoming key
            // and silently not stick — the palette then eats keystrokes
            // instead of typing into the search field. Re-assert once the
            // window has settled; the false→true cycle forces SwiftUI to
            // re-apply focus even though the value was already true.
            try? await Task.sleep(for: .milliseconds(120))
            isSearchFocused = false
            try? await Task.sleep(for: .milliseconds(1))
            isSearchFocused = true
        }
        .onKeyPress(.tab) {
            viewModel.toggleBrowseList()
            return .handled
        }
        .onChange(of: viewModel.selectedIndex) { _, _ in
            viewModel.updatePreview()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.updatePreview()
        }
        .onKeyPress(.escape) {
            if !viewModel.cancelChainedFlow() {
                onDismiss()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.return) {
            Task {
                let shouldDismiss = await viewModel.executeSelected()
                if shouldDismiss {
                    onDismiss()
                }
            }
            return .handled
        }
    }

    /// Invisible buttons carrying the cmd+1…9 shortcuts: each activates the
    /// Nth visible row directly, so the whole working set is one chord away.
    private var quickJumpShortcuts: some View {
        ForEach(1..<10, id: \.self) { number in
            Button("") {
                quickJump(to: number - 1)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func quickJump(to index: Int) {
        guard index < viewModel.filteredItems.count else { return }
        viewModel.selectedIndex = index
        Task {
            if await viewModel.executeSelected() {
                onDismiss()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Label("Toggle sessions sidebar", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isSidebarVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("b", modifiers: .command)
            .help("Toggle sessions sidebar (⌘B)")

            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField(viewModel.placeholder, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(Design.searchFont)
                .focused($isSearchFocused)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var contentArea: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sessionSidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            commandList
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Design.sectionHeaderFont)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Sessions")

            if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No tmux sessions",
                    systemImage: "terminal",
                    description: Text("Start tmux to see sessions here.")
                )
            } else {
                SessionListView(
                    sessions: viewModel.sessions,
                    onSelectSession: { session in
                        Task {
                            await viewModel.switchToSession(session)
                            onDismiss()
                        }
                    },
                    onSelectWindow: { session, windowIndex in
                        Task {
                            await viewModel.switchToWindow(session: session, windowIndex: windowIndex)
                            onDismiss()
                        }
                    }
                )
            }
        }
        .frame(width: 220)
    }

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(viewModel.listHeader)

            if viewModel.isAgentListEmpty {
                ContentUnavailableView(
                    "All quiet",
                    systemImage: "sparkles",
                    description: Text("No agents are working or waiting on you.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.filteredItems.indices, id: \.self) { index in
                                let item = viewModel.filteredItems[index]
                                if let section = item.sectionTitle {
                                    sectionHeader(section)
                                }
                                CommandRowView(
                                    item: item,
                                    isSelected: viewModel.selectedIndex == index,
                                    shortcutHint: index < 9 ? "⌘\(index + 1)" : nil
                                )
                                .id(index)
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    Task {
                                        let shouldDismiss = await viewModel.executeSelected()
                                        if shouldDismiss {
                                            onDismiss()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Preview")

            if let window = viewModel.selectedWindow, viewModel.previewContent != nil {
                HStack(spacing: 8) {
                    Text(window.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(previewMeta(for: window))
                        .font(Design.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("live")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Group {
                if let capture = viewModel.previewContent {
                    TerminalPreviewView(capture: capture)
                        .clipShape(.rect(cornerRadius: Design.previewCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.previewCornerRadius)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        }
                } else {
                    Text("Select a window to preview its contents")
                        .font(Design.rowSubtitleFont)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "~/projects/julia · ⎇ main"-style context line for the preview.
    private func previewMeta(for window: TmuxWindow) -> String {
        var parts: [String] = []
        if let path = window.currentPath {
            let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
            parts.append(path.hasPrefix(trimmedHome) ? "~" + path.dropFirst(trimmedHome.count) : path)
        }
        if let branch = window.gitBranch {
            parts.append("⎇ \(branch)")
        }
        return parts.joined(separator: " · ")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
    }
}

#Preview {
    PaletteView(
        viewModel: {
            let vm = PaletteViewModel()
            vm.sessions = [
                TmuxSession(
                    id: "$0",
                    name: "dev",
                    windows: [
                        TmuxWindow(id: "@0", index: 0, name: "nvim", sessionName: "dev", isActive: true),
                        TmuxWindow(id: "@1", index: 1, name: "shell", sessionName: "dev")
                    ],
                    isAttached: true
                ),
                TmuxSession(
                    id: "$1",
                    name: "work",
                    windows: [
                        TmuxWindow(id: "@3", index: 0, name: "main", sessionName: "work", isActive: true)
                    ]
                )
            ]
            return vm
        }(),
        onDismiss: {}
    )
    .padding()
}
