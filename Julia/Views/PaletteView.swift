import SwiftUI

struct PaletteView: View {
    @Bindable var viewModel: PaletteViewModel
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            contentArea
        }
        .frame(width: 600, height: 400)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .onAppear {
            viewModel.searchText = ""
            viewModel.selectedIndex = 0
            isSearchFocused = true
            viewModel.refresh()
        }
        .onKeyPress(.escape) {
            onDismiss()
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
                await viewModel.executeSelected()
                onDismiss()
            }
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search sessions, windows, or commands...", text: $viewModel.searchText)
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
            sessionSidebar
            Divider()
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
                                isSelected: viewModel.selectedIndex == index
                            )
                            .id(index)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                Task {
                                    await viewModel.executeSelected()
                                    onDismiss()
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
