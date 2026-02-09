import SwiftUI

/// Status indicator pill for idle state
public struct StatusPill: View {
    let icon: String
    let label: String
    let status: Status

    public enum Status {
        case ready
        case info
        case warning
        case error

        var color: Color {
            switch self {
            case .ready: return Ocean.success
            case .info: return Ocean.accent
            case .warning: return Ocean.warning
            case .error: return Ocean.error
            }
        }

        var bgOpacity: Double {
            switch self {
            case .ready, .info: return 0.15
            case .warning, .error: return 0.2
            }
        }
    }

    public init(icon: String, label: String, status: Status = .ready) {
        self.icon = icon
        self.label = label
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(status.color)

            Text(label)
                .font(Ocean.ui(11, weight: .medium))
                .foregroundColor(status == .info ? Ocean.text : status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(status.bgOpacity))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

#if DEBUG
struct StatusPill_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            StatusPill(icon: "checkmark", label: "Docker", status: .ready)
            StatusPill(icon: "checkmark", label: "Image", status: .ready)
            StatusPill(icon: "info.circle", label: "Port 18789", status: .info)
            StatusPill(icon: "exclamationmark.triangle", label: "Warning", status: .warning)
        }
        .padding()
        .background(Ocean.bg)
    }
}
#endif
