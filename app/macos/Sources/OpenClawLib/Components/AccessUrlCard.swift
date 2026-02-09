import SwiftUI
import AppKit

/// Access URL card with copy and open buttons
public struct AccessUrlCard: View {
    let url: String
    let onCopy: () -> Void
    let onOpen: () -> Void

    @State private var copied = false

    public init(url: String, onCopy: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.url = url
        self.onCopy = onCopy
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Globe icon
            ZStack {
                Circle()
                    .fill(Ocean.accent.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundColor(Ocean.accent)
            }

            // URL text
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCESS URL")
                    .font(Ocean.mono(10, weight: .medium))
                    .foregroundColor(Ocean.textDim)
                    .tracking(1)

                Text(url)
                    .font(Ocean.mono(16, weight: .medium))
                    .foregroundColor(Ocean.text)
            }

            Spacer()

            // Buttons
            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    copied = true
                    onCopy()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy")
                            .font(Ocean.ui(12, weight: .medium))
                    }
                    .foregroundColor(Ocean.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ocean.surface)
                    .cornerRadius(Ocean.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Ocean.buttonRadius)
                            .stroke(Ocean.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("Open")
                            .font(Ocean.ui(12, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Ocean.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ocean.accentGradient)
                    .cornerRadius(Ocean.buttonRadius)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Ocean.surface)
        .cornerRadius(Ocean.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Ocean.cardRadius)
                .stroke(Ocean.border, lineWidth: 1)
        )
    }
}

#if DEBUG
struct AccessUrlCard_Previews: PreviewProvider {
    static var previews: some View {
        AccessUrlCard(
            url: "http://localhost:3000/openclaw?token=abc123",
            onCopy: {},
            onOpen: {}
        )
        .padding()
        .background(Ocean.bg)
    }
}
#endif
