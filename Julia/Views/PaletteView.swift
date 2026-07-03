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
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .onAppear {
            viewModel.mode = .browsing
            viewModel.searchText = ""
            viewModel.selectedIndex = 0
            viewModel.previewContent = nil
            isSearchFocused = true
            viewModel.refresh()
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
                .foregroundStyle(.secondary)

            TextField(viewModel.placeholder, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
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

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if viewModel.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No tmux sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("Actions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredItems.indices, id: \.self) { index in
                            let item = viewModel.filteredItems[index]
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

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preview")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Group {
                if let capture = viewModel.previewContent {
                    TerminalPreviewView(capture: capture)
                } else {
                    Text("Select a window to preview its contents")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
