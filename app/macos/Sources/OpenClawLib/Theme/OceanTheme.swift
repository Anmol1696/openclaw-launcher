import SwiftUI

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Ocean Theme

/// Deep Ocean theme colors for OpenClaw Launcher
public enum Ocean {
    // MARK: Backgrounds

    /// Main window background - #0a0f1a
    public static let bg = Color(hex: "#0a0f1a")

    /// Surface elements (cards, panels) - #0f1629
    public static let surface = Color(hex: "#0f1629")

    /// Elevated cards - #151d35
    public static let card = Color(hex: "#151d35")

    // MARK: Accent

    /// Primary accent - #00d4aa (teal)
    public static let accent = Color(hex: "#00d4aa")

    /// Dimmed accent for backgrounds - 15% opacity
    public static let accentDim = Color(hex: "#00d4aa").opacity(0.15)

    /// Bright accent for glow effects - #00ffcc
    public static let accentGlow = Color(hex: "#00ffcc")

    // MARK: Text

    /// Primary text - #e8f4f8
    public static let text = Color(hex: "#e8f4f8")

    /// Secondary/dimmed text - #6b8a99
    public static let textDim = Color(hex: "#6b8a99")

    // MARK: Status

    /// Success state (same as accent) - #00d4aa
    public static let success = Color(hex: "#00d4aa")

    /// Warning state - #ff9f43
    public static let warning = Color(hex: "#ff9f43")

    /// Error state - #ff6b6b
    public static let error = Color(hex: "#ff6b6b")

    /// Info state - #4da6ff
    public static let info = Color(hex: "#4da6ff")

    // MARK: Border

    /// Default border - accent at 20% opacity
    public static let border = Color(hex: "#00d4aa").opacity(0.2)

    /// Warning border
    public static let borderWarning = Color(hex: "#ff9f43").opacity(0.3)

    /// Error border
    public static let borderError = Color(hex: "#ff6b6b").opacity(0.3)
}

// MARK: - Gradients

extension Ocean {
    /// Accent gradient for buttons and highlights
    public static let accentGradient = LinearGradient(
        colors: [accent, accentGlow],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Logo background gradient
    public static let logoGradient = LinearGradient(
        colors: [accent, Color(hex: "#00a080")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Progress bar gradient
    public static let progressGradient = LinearGradient(
        colors: [accent, accentGlow],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Fonts

extension Ocean {
    /// Monospace font for code, times, data
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI font
    public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Spacing & Sizing

extension Ocean {
    /// Corner radius for cards
    public static let cardRadius: CGFloat = 10

    /// Corner radius for buttons
    public static let buttonRadius: CGFloat = 6

    /// Corner radius for badges
    public static let badgeRadius: CGFloat = 4

    /// Standard padding
    public static let padding: CGFloat = 16

    /// Small padding
    public static let paddingSmall: CGFloat = 8

    /// Large padding
    public static let paddingLarge: CGFloat = 24
}
