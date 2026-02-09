import SwiftUI

/// Card container with Ocean theme styling
public struct OceanCard<Content: View, Header: View>: View {
    let content: Content
    let header: Header?

    public init(
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView {
        self.content = content()
        self.header = nil
    }

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let header = header {
                header
                    .padding(.horizontal, Ocean.padding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Ocean.border)
            }

            content
        }
        .background(Ocean.surface)
        .cornerRadius(Ocean.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Ocean.cardRadius)
                .stroke(Ocean.border, lineWidth: 1)
        )
    }
}

// MARK: - Card Header Helper

/// Standard card header with status indicator
public struct OceanCardHeader: View {
    let statusIndicator: PulseIndicator.Status
    let title: String
    let badge: String?
    let badgeStyle: OceanBadge.Style

    public init(
        status: PulseIndicator.Status,
        title: String,
        badge: String? = nil,
        badgeStyle: OceanBadge.Style = .default
    ) {
        self.statusIndicator = status
        self.title = title
        self.badge = badge
        self.badgeStyle = badgeStyle
    }

    public var body: some View {
        HStack {
            PulseIndicator(status: statusIndicator)

            Text(title)
                .font(Ocean.ui(14, weight: .medium))
                .foregroundColor(Ocean.text)

            Spacer()

            if let badge = badge {
                OceanBadge(badge, style: badgeStyle)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OceanCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Card with header
            OceanCard {
                OceanCardHeader(
                    status: .success,
                    title: "Environment Running",
                    badge: "lockdown"
                )
            } content: {
                VStack(spacing: 8) {
                    Text("Content goes here")
                        .foregroundColor(Ocean.textDim)
                }
                .padding(Ocean.padding)
            }

            // Card without header
            OceanCard {
                Text("Simple card content")
                    .foregroundColor(Ocean.text)
                    .padding(Ocean.padding)
            }
        }
        .padding(40)
        .background(Ocean.bg)
    }
}
#endif
