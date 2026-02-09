import SwiftUI
import AppKit

/// Card displaying key-value information rows
public struct InfoCard: View {
    let rows: [InfoRow]

    public struct InfoRow: Identifiable {
        public let id = UUID()
        public let label: String
        public let value: String
        public let copyable: Bool
        public let isConnected: Bool

        public init(
            label: String,
            value: String,
            copyable: Bool = false,
            isConnected: Bool = false
        ) {
            self.label = label
            self.value = value
            self.copyable = copyable
            self.isConnected = isConnected
        }
    }

    public init(rows: [InfoRow]) {
        self.rows = rows
    }

    public var body: some View {
        OceanCard {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    InfoRowView(row: row)

                    if index < rows.count - 1 {
                        Divider()
                            .background(Ocean.border.opacity(0.3))
                    }
                }
            }
            .padding(Ocean.padding)
        }
    }
}

// MARK: - Info Row View

private struct InfoRowView: View {
    let row: InfoCard.InfoRow

    var body: some View {
        HStack {
            // Label
            Text(row.label.uppercased())
                .font(Ocean.mono(10))
                .foregroundColor(Ocean.textDim)
                .tracking(0.5)

            Spacer()

            // Value
            if row.isConnected {
                ConnectedBadge()
            } else {
                HStack(spacing: 8) {
                    Text(row.value)
                        .font(Ocean.mono(13))
                        .foregroundColor(Ocean.text)

                    if row.copyable {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.value, forType: .string)
                        } label: {
                            Text("📋")
                                .font(.system(size: 12))
                                .foregroundColor(Ocean.textDim)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Connected Badge

private struct ConnectedBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Ocean.success)
                .frame(width: 6, height: 6)

            Text("Connected")
                .font(Ocean.ui(11))
                .foregroundColor(Ocean.success)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct InfoCard_Previews: PreviewProvider {
    static var previews: some View {
        InfoCard(rows: [
            .init(label: "Gateway URL", value: "http://localhost:8080", copyable: true),
            .init(label: "Status", value: "", isConnected: true),
        ])
        .padding(20)
        .background(Ocean.bg)
    }
}
#endif
