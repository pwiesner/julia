import SwiftUI

/// The settings health section: each external dependency with a status
/// dot and its actually-detected state, so "why is julia not showing X"
/// answers itself here instead of in a debugging session.
struct HealthSectionView: View {
    @State private var dependencies: [HealthService.Dependency] = []

    var body: some View {
        Section("Health") {
            if dependencies.isEmpty {
                Text("Checking…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dependencies) { dependency in
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text(dependency.detail)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            // Hooks modify the user's tmux server, so
                            // installing is a button, never automatic.
                            if HealthService.canInstallVisitHooks(dependency) {
                                Button("Install") {
                                    installVisitHooks()
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: dependency.level))
                                .frame(width: 8, height: 8)
                            Text(dependency.name)
                        }
                    }
                }
            }
        }
        .task {
            // Rows land as each probe finishes; a slow gh check can't
            // hold tmux and beeper hostage at "Checking…".
            dependencies = []
            for await dependency in HealthService.check() {
                dependencies.append(dependency)
                dependencies.sort { $0.rank < $1.rank }
            }
        }
    }

    private func installVisitHooks() {
        Task {
            await HealthService.installVisitHooks()
            dependencies = []
            for await dependency in HealthService.check() {
                dependencies.append(dependency)
                dependencies.sort { $0.rank < $1.rank }
            }
        }
    }

    /// Color plus the wording in `detail` carry the state together, so
    /// differentiate-without-color users aren't reading tea leaves.
    private func color(for level: HealthService.Dependency.Level) -> Color {
        switch level {
        case .good: .green
        case .limited: .orange
        case .missing: .red
        }
    }
}
