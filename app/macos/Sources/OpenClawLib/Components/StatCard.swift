import SwiftUI

/// Stats card for the running dashboard 2x2 grid
public struct StatCard: View {
    let label: String
    let value: String
    let valueColor: Color

    public init(label: String, value: String, valueColor: Color = Ocean.accent) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Ocean.mono(10, weight: .medium))
                .foregroundColor(Ocean.textDim)
                .tracking(1)

            Text(value)
                .font(Ocean.mono(24, weight: .medium))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
struct StatCard_Previews: PreviewProvider {
    static var previews: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(label: "UPTIME", value: "4m 32s", valueColor: Ocean.accent)
            StatCard(label: "PORT", value: "3000", valueColor: Ocean.text)
            StatCard(label: "CPU", value: "2.3%", valueColor: Ocean.accent)
            StatCard(label: "MEMORY", value: "128 MB", valueColor: Ocean.text)
        }
        .padding()
        .background(Ocean.bg)
    }
}
#endif
