import SwiftUI

/// Status panel showing current state, steps, and progress
public struct StatusPanel: View {
    let status: PulseIndicator.Status
    let statusText: String
    let badge: String
    let badgeStyle: OceanBadge.Style
    let steps: [StepInfo]
    let progress: Double?
    let progressLeftText: String?
    let progressRightText: String?

    public struct StepInfo: Identifiable {
        public let id = UUID()
        public let status: OceanStepRow.Status
        public let label: String
        public let time: String?

        public init(status: OceanStepRow.Status, label: String, time: String? = nil) {
            self.status = status
            self.label = label
            self.time = time
        }
    }

    public init(
        status: PulseIndicator.Status,
        statusText: String,
        badge: String = "lockdown",
        badgeStyle: OceanBadge.Style = .default,
        steps: [StepInfo],
        progress: Double? = nil,
        progressLeftText: String? = nil,
        progressRightText: String? = nil
    ) {
        self.status = status
        self.statusText = statusText
        self.badge = badge
        self.badgeStyle = badgeStyle
        self.steps = steps
        self.progress = progress
        self.progressLeftText = progressLeftText
        self.progressRightText = progressRightText
    }

    public var body: some View {
        OceanCard {
            // Header
            OceanCardHeader(
                status: status,
                title: statusText,
                badge: badge,
                badgeStyle: badgeStyle
            )
        } content: {
            VStack(spacing: 0) {
                // Steps
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    OceanStepRow(
                        status: step.status,
                        label: step.label,
                        time: step.time
                    )

                    if index < steps.count - 1 {
                        Divider()
                            .background(Ocean.border.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, Ocean.padding)
            .padding(.vertical, Ocean.paddingSmall)

            // Progress bar (if provided)
            if let progress = progress {
                VStack(spacing: 0) {
                    Divider()
                        .background(Ocean.border)

                    OceanProgressBar(
                        progress: progress,
                        leftText: progressLeftText,
                        rightText: progressRightText
                    )
                    .padding(Ocean.padding)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StatusPanel_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Idle state
            StatusPanel(
                status: .idle,
                statusText: "Ready to Launch",
                steps: [
                    .init(status: .pending, label: "Docker connection"),
                    .init(status: .pending, label: "Container image"),
                    .init(status: .pending, label: "Network setup"),
                    .init(status: .pending, label: "Gateway service"),
                    .init(status: .pending, label: "Health check"),
                ]
            )

            // Running state
            StatusPanel(
                status: .success,
                statusText: "Environment Running",
                steps: [
                    .init(status: .done, label: "Docker connection", time: "1.2s"),
                    .init(status: .done, label: "Container image", time: "4.8s"),
                    .init(status: .done, label: "Network setup", time: "0.3s"),
                    .init(status: .done, label: "Gateway service", time: "2.1s"),
                    .init(status: .done, label: "Health check", time: "0.8s"),
                ],
                progress: 1.0,
                progressLeftText: "5 of 5 steps",
                progressRightText: "9.2s total"
            )
        }
        .padding(20)
        .background(Ocean.bg)
    }
}
#endif
