import SwiftUI

/// Animated pulsing status indicator dot
public struct PulseIndicator: View {
    public enum Status {
        case idle      // Gray, no animation
        case active    // Teal, pulsing
        case success   // Green, pulsing
        case warning   // Orange, pulsing
        case error     // Red, no animation

        var color: Color {
            switch self {
            case .idle: return Ocean.textDim
            case .active: return Ocean.accent
            case .success: return Ocean.success
            case .warning: return Ocean.warning
            case .error: return Ocean.error
            }
        }

        var shouldPulse: Bool {
            switch self {
            case .idle, .error: return false
            case .active, .success, .warning: return true
            }
        }
    }

    let status: Status
    let size: CGFloat

    @State private var isPulsing = false

    public init(status: Status, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .shadow(
                color: status.shouldPulse ? status.color.opacity(isPulsing ? 0.6 : 0) : .clear,
                radius: isPulsing ? size : 0
            )
            .animation(
                status.shouldPulse
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if status.shouldPulse {
                    isPulsing = true
                }
            }
            .onChange(of: status) { _, newStatus in
                isPulsing = newStatus.shouldPulse
            }
    }
}

// MARK: - Preview

#if DEBUG
struct PulseIndicator_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            VStack {
                PulseIndicator(status: .idle)
                Text("Idle").font(Ocean.mono(10))
            }
            VStack {
                PulseIndicator(status: .active)
                Text("Active").font(Ocean.mono(10))
            }
            VStack {
                PulseIndicator(status: .success)
                Text("Success").font(Ocean.mono(10))
            }
            VStack {
                PulseIndicator(status: .warning)
                Text("Warning").font(Ocean.mono(10))
            }
            VStack {
                PulseIndicator(status: .error)
                Text("Error").font(Ocean.mono(10))
            }
        }
        .padding(40)
        .background(Ocean.bg)
        .foregroundColor(Ocean.text)
    }
}
#endif
