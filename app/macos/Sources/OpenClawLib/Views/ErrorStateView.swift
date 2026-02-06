import SwiftUI

/// Displays error states with icon, title, message, optional details, and action buttons
public struct ErrorStateView: View {
    public enum ErrorType {
        case dockerNotInstalled
        case dockerNotRunning
        case pullFailed(details: String)
        case portConflict(port: Int, suggestedPort: Int)
        case containerCrashed(exitCode: Int?)
        case generic(message: String)
    }

    let errorType: ErrorType
    let onRetry: () -> Void
    let onSecondary: (() -> Void)?
    let onTertiary: (() -> Void)?

    public init(
        errorType: ErrorType,
        onRetry: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        onTertiary: (() -> Void)? = nil
    ) {
        self.errorType = errorType
        self.onRetry = onRetry
        self.onSecondary = onSecondary
        self.onTertiary = onTertiary
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Icon
            Text(icon)
                .font(.system(size: 48))
                .padding(.bottom, 4)

            // Title
            Text(title)
                .font(Ocean.ui(18, weight: .semibold))
                .foregroundColor(Ocean.error)

            // Message
            Text(message)
                .font(Ocean.ui(13))
                .foregroundColor(Ocean.textDim)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            // Details box (for errors with extra info)
            if let details = details {
                ScrollView {
                    Text(details)
                        .font(Ocean.mono(11))
                        .foregroundColor(Ocean.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 80)
                .background(Ocean.bg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Ocean.borderError, lineWidth: 1)
                )
            }

            // Action buttons
            HStack(spacing: 12) {
                OceanButton(primaryButtonTitle, icon: primaryButtonIcon) {
                    onRetry()
                }

                if let secondary = onSecondary {
                    OceanButton(secondaryButtonTitle, variant: .secondary) {
                        secondary()
                    }
                }

                if let tertiary = onTertiary {
                    OceanButton(tertiaryButtonTitle, variant: .secondary) {
                        tertiary()
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Ocean.card)
        .cornerRadius(Ocean.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Ocean.cardRadius)
                .stroke(Ocean.borderError, lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var icon: String {
        switch errorType {
        case .dockerNotInstalled, .dockerNotRunning:
            return "🐳"
        case .pullFailed:
            return "📦"
        case .portConflict:
            return "🔌"
        case .containerCrashed:
            return "💥"
        case .generic:
            return "⚠️"
        }
    }

    private var title: String {
        switch errorType {
        case .dockerNotInstalled:
            return "Docker Not Installed"
        case .dockerNotRunning:
            return "Docker Not Running"
        case .pullFailed:
            return "Image Pull Failed"
        case .portConflict:
            return "Port Conflict"
        case .containerCrashed:
            return "Container Crashed"
        case .generic:
            return "Error"
        }
    }

    private var message: String {
        switch errorType {
        case .dockerNotInstalled:
            return "Docker Desktop is required to run OpenClaw. Please install it and try again."
        case .dockerNotRunning:
            return "Docker Desktop needs to be running. Start it and we'll retry automatically."
        case .pullFailed:
            return "Failed to download the container image. Check your internet connection."
        case .portConflict(let port, let suggested):
            return "Port \(port) is already in use. Would you like to use port \(suggested) instead?"
        case .containerCrashed(let exitCode):
            if let code = exitCode {
                return "The container exited unexpectedly with code \(code)."
            }
            return "The container exited unexpectedly."
        case .generic(let msg):
            return msg
        }
    }

    private var details: String? {
        switch errorType {
        case .pullFailed(let details):
            return details.isEmpty ? nil : details
        default:
            return nil
        }
    }

    private var primaryButtonTitle: String {
        switch errorType {
        case .dockerNotInstalled:
            return "Download Docker"
        case .dockerNotRunning:
            return "Retry Connection"
        case .pullFailed:
            return "Retry"
        case .portConflict(_, let suggested):
            return "Use Port \(suggested)"
        case .containerCrashed, .generic:
            return "Retry"
        }
    }

    private var primaryButtonIcon: String? {
        switch errorType {
        case .dockerNotInstalled:
            return "⬇"
        case .dockerNotRunning, .pullFailed, .containerCrashed, .generic:
            return "↻"
        case .portConflict:
            return nil
        }
    }

    private var secondaryButtonTitle: String {
        switch errorType {
        case .dockerNotInstalled, .dockerNotRunning:
            return "Open Docker"
        case .pullFailed:
            return "Use Cached"
        case .portConflict:
            return "Choose Port"
        case .containerCrashed:
            return "View Logs"
        case .generic:
            return "Dismiss"
        }
    }

    private var tertiaryButtonTitle: String {
        switch errorType {
        case .containerCrashed:
            return "Settings"
        default:
            return ""
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ErrorStateView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ErrorStateView(
                errorType: .dockerNotRunning,
                onRetry: {},
                onSecondary: {}
            )

            ErrorStateView(
                errorType: .pullFailed(details: "Error: timeout waiting for response\nNetwork unreachable"),
                onRetry: {},
                onSecondary: {}
            )

            ErrorStateView(
                errorType: .containerCrashed(exitCode: 137),
                onRetry: {},
                onSecondary: {},
                onTertiary: {}
            )
        }
        .padding(20)
        .background(Ocean.bg)
    }
}
#endif
