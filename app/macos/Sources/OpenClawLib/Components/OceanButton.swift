import SwiftUI

/// Styled button variants for Ocean theme
public struct OceanButton: View {
    public enum Variant {
        case primary    // Accent background, dark text
        case secondary  // Transparent, bordered
        case danger     // Error color, bordered
    }

    let title: String
    let icon: String?
    let variant: Variant
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        icon: String? = nil,
        variant: Variant = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Text(icon)
                }
                Text(title)
                    .font(Ocean.ui(13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background)
            .foregroundColor(foregroundColor)
            .cornerRadius(Ocean.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Ocean.buttonRadius)
                    .stroke(borderColor, lineWidth: variant == .primary ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var background: Color {
        guard isEnabled else { return Ocean.surface }
        switch variant {
        case .primary: return Ocean.accent
        case .secondary, .danger: return .clear
        }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Ocean.textDim }
        switch variant {
        case .primary: return Ocean.bg
        case .secondary: return Ocean.textDim
        case .danger: return Ocean.error
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return Ocean.border }
        switch variant {
        case .primary: return .clear
        case .secondary: return Ocean.border
        case .danger: return Ocean.borderError
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OceanButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            OceanButton("Launch", icon: "▶", variant: .primary) {}
            OceanButton("Cancel", variant: .secondary) {}
            OceanButton("Stop", icon: "■", variant: .danger) {}

            Divider()

            OceanButton("Disabled", variant: .primary) {}
                .disabled(true)
            OceanButton("Disabled", variant: .secondary) {}
                .disabled(true)
        }
        .padding(40)
        .background(Ocean.bg)
    }
}
#endif
