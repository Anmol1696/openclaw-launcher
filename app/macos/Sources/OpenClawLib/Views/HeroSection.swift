import SwiftUI

/// Hero section with logo, title, and subtitle
public struct HeroSection: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Logo with glow effect
            ZStack {
                // Glow behind logo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Ocean.accentDim, .clear],
                            center: .center,
                            startRadius: 15,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 100)
                    .offset(y: -10)

                // Logo
                Text("🐙")
                    .font(.system(size: 24))
                    .frame(width: 48, height: 48)
                    .background(Ocean.logoGradient)
                    .cornerRadius(12)
                    .shadow(color: Ocean.accent.opacity(0.25), radius: 6, y: 3)
            }

            // Title
            Text("OpenClaw")
                .font(Ocean.ui(22, weight: .bold))
                .foregroundColor(Ocean.text)

            // Subtitle
            HStack(spacing: 8) {
                Text("Isolated AI Agent")
                    .foregroundColor(Ocean.textDim)

                Circle()
                    .fill(Ocean.accent)
                    .frame(width: 4, height: 4)

                Text("Docker Powered")
                    .foregroundColor(Ocean.textDim)
            }
            .font(Ocean.ui(12))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Preview

#if DEBUG
struct HeroSection_Previews: PreviewProvider {
    static var previews: some View {
        HeroSection()
            .frame(width: 400)
            .background(Ocean.bg)
    }
}
#endif
