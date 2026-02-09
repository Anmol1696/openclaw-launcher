import SwiftUI

// MARK: - Section Header

/// Section header for settings groups
public struct SettingsSectionHeader: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(Ocean.mono(10, weight: .medium))
            .foregroundColor(Ocean.textDim)
            .tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

// MARK: - Toggle Row

/// Toggle row for boolean settings
public struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Ocean.ui(11))
                        .foregroundColor(Ocean.textDim)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Ocean.accent)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Dropdown Row

/// Dropdown row for selection settings
public struct SettingsDropdownRow<T: Hashable>: View {
    let title: String
    let subtitle: String?
    let options: [T]
    let optionLabel: (T) -> String
    @Binding var selection: T

    public init(
        _ title: String,
        subtitle: String? = nil,
        options: [T],
        optionLabel: @escaping (T) -> String,
        selection: Binding<T>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.optionLabel = optionLabel
        self._selection = selection
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Ocean.ui(11))
                        .foregroundColor(Ocean.textDim)
                }
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Stepper Row

/// Stepper row for numeric settings
public struct SettingsStepperRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String

    public init(
        _ title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        formatter: @escaping (Double) -> String = { "\(Int($0))" }
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.formatter = formatter
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Ocean.ui(11))
                        .foregroundColor(Ocean.textDim)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(formatter(value))
                    .font(Ocean.mono(12))
                    .foregroundColor(Ocean.text)
                    .frame(width: 50, alignment: .trailing)

                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Text Field Row

/// Text field row for string/number input
public struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: String
    let placeholder: String

    public init(
        _ title: String,
        subtitle: String? = nil,
        value: Binding<String>,
        placeholder: String = ""
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Ocean.ui(11))
                        .foregroundColor(Ocean.textDim)
                }
            }

            Spacer()

            TextField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(Ocean.mono(12))
                .foregroundColor(Ocean.text)
                .padding(8)
                .frame(width: 100)
                .background(Ocean.bg)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Ocean.border, lineWidth: 1)
                )
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            SettingsSectionHeader("General")

            SettingsToggleRow("Launch at startup", subtitle: "Start when you log in", isOn: .constant(true))
            Divider().background(Ocean.border.opacity(0.3))

            SettingsToggleRow("Show in menu bar", isOn: .constant(true))
            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Container")

            SettingsDropdownRow(
                "Memory limit",
                options: ["1 GB", "2 GB", "4 GB"],
                optionLabel: { $0 },
                selection: .constant("2 GB")
            )
        }
        .padding(20)
        .background(Ocean.surface)
        .frame(width: 350)
    }
}
#endif
