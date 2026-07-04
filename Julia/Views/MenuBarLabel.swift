import SwiftUI

/// The menu bar icon, with a count when Claudes are waiting on the user —
/// the "someone needs you" signal without opening anything.
struct MenuBarLabel: View {
    let monitor: AgentMonitorService

    var body: some View {
        if monitor.waitingCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "terminal.fill")
                Text("\(monitor.waitingCount)")
                    .fontWeight(.semibold)
            }
        } else {
            Image(systemName: "terminal")
        }
    }
}
