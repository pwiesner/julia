import SwiftUI

struct CommandRowView: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : (item.iconColor ?? .secondary))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 4) {
        CommandRowView(
            item: PaletteItem(
                title: "dev",
                subtitle: "Session with 3 windows",
                icon: "terminal",
                action: .switchSession("dev")
            ),
            isSelected: false
        )
        CommandRowView(
            item: PaletteItem(
                title: "work",
                subtitle: "Session with 2 windows",
                icon: "terminal",
                action: .switchSession("work")
            ),
            isSelected: true
        )
        CommandRowView(
            item: PaletteItem(
                title: "New session",
                subtitle: nil,
                icon: "plus.circle",
                action: .command(.newSession)
            ),
            isSelected: false
        )
    }
    .padding()
    .frame(width: 400)
    .background(.regularMaterial)
}
