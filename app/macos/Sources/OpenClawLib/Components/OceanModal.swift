import SwiftUI

/// Base modal component with Ocean theme styling
public struct OceanModal<Content: View>: View {
    let icon: String?
    let title: String
    let message: String?
    let content: Content?
    let primaryAction: ModalAction?
    let secondaryAction: ModalAction?
    let onDismiss: () -> Void

    public struct ModalAction {
        let title: String
        let variant: OceanButton.Variant
        let action: () -> Void

        public init(
            _ title: String,
            variant: OceanButton.Variant = .primary,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.variant = variant
            self.action = action
        }
    }

    public init(
        icon: String? = nil,
        title: String,
        message: String? = nil,
        primaryAction: ModalAction? = nil,
        secondaryAction: ModalAction? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Modal card
            VStack(spacing: 16) {
                // Icon
                if let icon = icon {
                    Text(icon)
                        .font(.system(size: 40))
                        .padding(.top, 8)
                }

                // Title
                Text(title)
                    .font(Ocean.ui(16, weight: .semibold))
                    .foregroundColor(Ocean.text)
                    .multilineTextAlignment(.center)

                // Message
                if let message = message {
                    Text(message)
                        .font(Ocean.ui(13))
                        .foregroundColor(Ocean.textDim)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }

                // Custom content
                if let content = content {
                    content
                }

                // Actions
                HStack(spacing: 12) {
                    if let secondary = secondaryAction {
                        OceanButton(secondary.title, variant: secondary.variant) {
                            secondary.action()
                        }
                    }

                    if let primary = primaryAction {
                        OceanButton(primary.title, variant: primary.variant) {
                            primary.action()
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(width: 320)
            .background(Ocean.card)
            .cornerRadius(Ocean.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Ocean.cardRadius)
                    .stroke(Ocean.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
        }
    }
}

// Convenience init without custom content
extension OceanModal where Content == EmptyView {
    public init(
        icon: String? = nil,
        title: String,
        message: String? = nil,
        primaryAction: ModalAction? = nil,
        secondaryAction: ModalAction? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.onDismiss = onDismiss
        self.content = nil
    }
}

// MARK: - Confirm Stop Modal

public struct ConfirmStopModal: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        OceanModal(
            icon: "⚠️",
            title: "Stop Environment?",
            message: "This will stop the running container. Any unsaved work in agent sessions may be lost.",
            primaryAction: .init("Stop", variant: .danger) {
                onConfirm()
            },
            secondaryAction: .init("Cancel", variant: .secondary) {
                onCancel()
            },
            onDismiss: onCancel
        )
    }
}

// MARK: - Confirm Reset Modal

public struct ConfirmResetModal: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        OceanModal(
            icon: "🗑️",
            title: "Reset Everything?",
            message: "This will remove the container, all local configuration, and authentication. You'll need to set up again.",
            primaryAction: .init("Reset", variant: .danger) {
                onConfirm()
            },
            secondaryAction: .init("Cancel", variant: .secondary) {
                onCancel()
            },
            onDismiss: onCancel
        )
    }
}

// MARK: - Preview

#if DEBUG
struct OceanModal_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Ocean.bg.ignoresSafeArea()

            ConfirmStopModal(onConfirm: {}, onCancel: {})
        }
    }
}
#endif
