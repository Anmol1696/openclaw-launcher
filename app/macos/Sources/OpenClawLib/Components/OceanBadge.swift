import SwiftUI

/// Small status badge with text
public struct OceanBadge: View {
    public enum Style {
        case `default`  // Accent dim
        case warning    // Warning color
        case error      // Error color
        case success    // Success/accent

        var backgroundColor: Color {
            switch self {
            case .default, .success: return Ocean.accentDim
            case .warning: return Ocean.warning.opacity(0.15)
            case .error: return Ocean.error.opacity(0.15)
            }
        }

        var textColor: Color {
            switch self {
            case .default, .success: return Ocean.accent
            case .warning: return Ocean.warning
            case .error: return Ocean.error
            }
        }

        var borderColor: Color {
            switch self {
            case .default, .success: return Ocean.border
            case .warning: return Ocean.borderWarning
            case .error: return Ocean.borderError
            }
        }
    }

    let text: String
    let style: Style

    public init(_ text: String, style: Style = .default) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(Ocean.mono(10, weight: .medium))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(style.backgroundColor)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(style.borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Preview

#if DEBUG
struct OceanBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            OceanBadge("lockdown")
            OceanBadge("stopping", style: .warning)
            OceanBadge("error", style: .error)
            OceanBadge("active", style: .success)
        }
        .padding(40)
        .background(Ocean.bg)
    }
}
#endif
