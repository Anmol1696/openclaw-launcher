import SwiftUI

/// Clean idle view shown when app is ready to launch
/// No checklist - just status pills and a welcoming message
public struct IdleContentView: View {
    let port: Int

    public init(port: Int) {
        self.port = port
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("Ready to Launch")
                    .font(Ocean.ui(20, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Spacer()

                OceanBadge("Lockdown", style: .default)
            }
            .padding(.bottom, 20)

            // Status pills row
            HStack(spacing: 12) {
                StatusPill(icon: "checkmark.circle.fill", label: "Docker", status: .ready)
                StatusPill(icon: "checkmark.circle.fill", label: "Image", status: .ready)
                StatusPill(icon: "network", label: "Port \(port)", status: .info)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Center message
            VStack(spacing: 12) {
                Image(systemName: "play.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Ocean.accent.opacity(0.6))

                Text("Click Launch to start OpenClaw")
                    .font(Ocean.ui(14))
                    .foregroundColor(Ocean.textDim)

                Text("All systems ready")
                    .font(Ocean.ui(12))
                    .foregroundColor(Ocean.textDim.opacity(0.7))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct IdleContentView_Previews: PreviewProvider {
    static var previews: some View {
        IdleContentView(port: 18789)
            .padding(20)
            .background(Ocean.bg)
            .frame(width: 500, height: 400)
    }
}
#endif
