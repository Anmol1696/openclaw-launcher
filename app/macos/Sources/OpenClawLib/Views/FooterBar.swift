import SwiftUI

/// Footer bar with stats and action buttons
public struct FooterBar: View {
    let cpuText: String?
    let memoryText: String?
    let buttons: [FooterButton]
    let onSettings: (() -> Void)?

    public struct FooterButton: Identifiable {
        public let id = UUID()
        public let title: String
        public let icon: String?
        public let variant: OceanButton.Variant
        public let disabled: Bool
        public let action: () -> Void

        public init(
            title: String,
            icon: String? = nil,
            variant: OceanButton.Variant = .primary,
            disabled: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.variant = variant
            self.disabled = disabled
            self.action = action
        }
    }

    public init(
        cpuText: String? = nil,
        memoryText: String? = nil,
        buttons: [FooterButton],
        onSettings: (() -> Void)? = nil
    ) {
        self.cpuText = cpuText
        self.memoryText = memoryText
        self.buttons = buttons
        self.onSettings = onSettings
    }

    public var body: some View {
        HStack {
            // Stats + Settings button
            HStack(spacing: 12) {
                // Settings gear button
                if let onSettings = onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(Ocean.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }

                HStack(spacing: 16) {
                    if let cpu = cpuText {
                        StatItem(icon: "◉", label: "CPU", value: cpu)
                    } else {
                        StatItem(icon: "◉", label: "CPU", value: "—")
                    }

                    if let mem = memoryText {
                        StatItem(icon: "▣", label: "Memory", value: mem)
                    } else {
                        StatItem(icon: "▣", label: "Memory", value: "—")
                    }
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 8) {
                ForEach(buttons) { button in
                    OceanButton(
                        button.title,
                        icon: button.icon,
                        variant: button.variant,
                        action: button.action
                    )
                    .disabled(button.disabled)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Ocean.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Ocean.border),
            alignment: .top
        )
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.system(size: 10))
            Text("\(label) \(value)")
                .font(Ocean.mono(11))
        }
        .foregroundColor(Ocean.textDim)
    }
}

// MARK: - Preview

#if DEBUG
struct FooterBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Idle state
            FooterBar(
                buttons: [
                    .init(title: "Launch", icon: "▶", action: {})
                ]
            )

            // Running state
            FooterBar(
                cpuText: "8%",
                memoryText: "512 MB",
                buttons: [
                    .init(title: "Open Browser", icon: "🌐", action: {}),
                    .init(title: "Stop", icon: "■", variant: .secondary, action: {})
                ]
            )

            // Stopping state
            FooterBar(
                cpuText: "5%",
                memoryText: "256 MB",
                buttons: [
                    .init(title: "Stopping...", variant: .secondary, disabled: true, action: {})
                ]
            )
        }
        .background(Ocean.bg)
    }
}
#endif
