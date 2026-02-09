import SwiftUI

/// Row displaying a launch step with icon, label, and time
public struct OceanStepRow: View {
    public enum Status {
        case pending    // Empty circle
        case active     // Spinning indicator
        case done       // Checkmark
        case error      // X mark
        case warning    // Warning

        var iconColor: Color {
            switch self {
            case .pending: return Ocean.textDim.opacity(0.5)
            case .active: return Ocean.accent
            case .done: return Ocean.accent
            case .error: return Ocean.error
            case .warning: return Ocean.warning
            }
        }

        var labelColor: Color {
            switch self {
            case .done: return Ocean.text
            case .active: return Ocean.text
            default: return Ocean.textDim
            }
        }
    }

    let status: Status
    let label: String
    let time: String?

    @State private var isRotating = false

    public init(status: Status, label: String, time: String? = nil) {
        self.status = status
        self.label = label
        self.time = time
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .stroke(status.iconColor.opacity(status == .pending ? 0.5 : 1), lineWidth: 1.5)
                    .frame(width: 20, height: 20)

                switch status {
                case .pending:
                    EmptyView()
                case .active:
                    // Spinning arc
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(status.iconColor, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                        .animation(
                            .linear(duration: 1).repeatForever(autoreverses: false),
                            value: isRotating
                        )
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(status.iconColor)
                case .error:
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(status.iconColor)
                case .warning:
                    Text("!")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(status.iconColor)
                }
            }
            .frame(width: 24, height: 24)

            // Label
            Text(label)
                .font(Ocean.ui(13))
                .foregroundColor(status.labelColor)

            Spacer()

            // Time (only show if provided and meaningful)
            if let time = time, !time.isEmpty {
                Text(time)
                    .font(Ocean.mono(11))
                    .foregroundColor(Ocean.textDim)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if status == .active {
                isRotating = true
            }
        }
        .onChange(of: status) { _, newStatus in
            isRotating = newStatus == .active
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OceanStepRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            OceanStepRow(status: .done, label: "Docker connection")
            Divider().background(Ocean.border.opacity(0.3))
            OceanStepRow(status: .done, label: "Container image")
            Divider().background(Ocean.border.opacity(0.3))
            OceanStepRow(status: .active, label: "Gateway service")
            Divider().background(Ocean.border.opacity(0.3))
            OceanStepRow(status: .pending, label: "Health check")
            Divider().background(Ocean.border.opacity(0.3))
            OceanStepRow(status: .error, label: "Network setup", time: "failed")
            Divider().background(Ocean.border.opacity(0.3))
            OceanStepRow(status: .warning, label: "Using cached image")
        }
        .padding(16)
        .background(Ocean.surface)
        .cornerRadius(10)
        .padding(40)
        .background(Ocean.bg)
    }
}
#endif
