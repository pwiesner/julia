import SwiftUI

struct CommandRowView: View {
    let item: PaletteItem
    let isSelected: Bool
    var shortcutHint: String? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // When selected, the chip flips to solid white so the glyph can
            // keep its state color — a blue "waiting" bubble must stay blue
            // on the blue selection, not wash out to white.
            RoundedRectangle(cornerRadius: Design.chipCornerRadius)
                .fill(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.primary.opacity(0.06)))
                .frame(width: Design.iconChipSize, height: Design.iconChipSize)
                .overlay {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconStyle)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Design.rowTitleFont)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Design.rowSubtitleFont)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if let shortcutHint {
                Text(shortcutHint)
                    .font(Design.shortcutHintFont)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, Design.rowHorizontalPadding)
        .padding(.vertical, Design.rowVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: Design.rowCornerRadius)
                .fill(rowFill)
        }
        .opacity(item.isStale && !isSelected && !isHovered ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var iconStyle: AnyShapeStyle {
        if let color = item.iconColor {
            AnyShapeStyle(color)
        } else if isSelected {
            AnyShapeStyle(Color.accentColor)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private var rowFill: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor)
        } else if isHovered {
            AnyShapeStyle(.primary.opacity(0.05))
        } else {
            AnyShapeStyle(.clear)
        }
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
            isSelected: false,
            shortcutHint: "⌘1"
        )
        CommandRowView(
            item: PaletteItem(
                title: "work",
                subtitle: "Session with 2 windows",
                icon: "terminal",
                action: .switchSession("work")
            ),
            isSelected: true,
            shortcutHint: "⌘2"
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
