import SwiftUI

/// Progress bar with gradient fill and optional meta text
public struct OceanProgressBar: View {
    let progress: Double  // 0.0 to 1.0
    let leftText: String?
    let rightText: String?
    let tint: Color?

    public init(
        progress: Double,
        leftText: String? = nil,
        rightText: String? = nil,
        tint: Color? = nil
    ) {
        self.progress = min(max(progress, 0), 1)
        self.leftText = leftText
        self.rightText = rightText
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Ocean.accentDim)
                        .frame(height: 3)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillGradient)
                        .frame(width: geometry.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)

            // Meta text
            if leftText != nil || rightText != nil {
                HStack {
                    if let left = leftText {
                        Text(left)
                            .font(Ocean.mono(10))
                            .foregroundColor(Ocean.textDim)
                    }
                    Spacer()
                    if let right = rightText {
                        Text(right)
                            .font(Ocean.mono(10))
                            .foregroundColor(Ocean.textDim)
                    }
                }
            }
        }
    }

    private var fillGradient: LinearGradient {
        if let tint = tint {
            return LinearGradient(
                colors: [tint, tint],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return Ocean.progressGradient
    }
}

// MARK: - Preview

#if DEBUG
struct OceanProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            OceanProgressBar(
                progress: 0.65,
                leftText: "3 of 5 steps",
                rightText: "6.3s"
            )

            OceanProgressBar(
                progress: 1.0,
                leftText: "Complete",
                rightText: "9.2s total"
            )

            OceanProgressBar(
                progress: 0.4,
                leftText: "Stopping...",
                tint: Ocean.warning
            )

            OceanProgressBar(progress: 0.25)
        }
        .padding(40)
        .background(Ocean.surface)
        .cornerRadius(10)
        .padding(20)
        .background(Ocean.bg)
    }
}
#endif
