import SwiftUI

/// Log entry model
public struct LogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let level: Level
    public let source: String
    public let message: String

    public enum Level: String, CaseIterable {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"

        var color: Color {
            switch self {
            case .info: return Ocean.info
            case .warn: return Ocean.warning
            case .error: return Ocean.error
            case .debug: return Ocean.textDim
            }
        }
    }

    public init(timestamp: Date = Date(), level: Level, source: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
    }

    /// Parse a log line from docker logs output
    public static func parse(_ line: String) -> LogEntry? {
        // Simple parsing - adjust based on actual log format
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try to detect level from content
        let level: Level
        let lowercased = trimmed.lowercased()
        if lowercased.contains("error") || lowercased.contains("err") {
            level = .error
        } else if lowercased.contains("warn") {
            level = .warn
        } else if lowercased.contains("debug") {
            level = .debug
        } else {
            level = .info
        }

        return LogEntry(level: level, source: "container", message: trimmed)
    }
}

/// Log viewer with filtering
public struct LogViewerView: View {
    @ObservedObject var launcher: OpenClawLauncher
    @Environment(\.dismiss) private var dismiss

    @State private var filter: LogEntry.Level? = nil
    @State private var entries: [LogEntry] = []
    @State private var isStreaming = false

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Container Logs")
                    .font(Ocean.ui(16, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Spacer()

                // Streaming indicator
                if isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Ocean.accent)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(Ocean.mono(10))
                            .foregroundColor(Ocean.accent)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Ocean.textDim)
                        .frame(width: 24, height: 24)
                        .background(Ocean.surface)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Ocean.surface)

            Divider().background(Ocean.border)

            // Filter bar
            HStack(spacing: 8) {
                FilterButton(label: "All", isSelected: filter == nil) {
                    filter = nil
                }

                ForEach(LogEntry.Level.allCases, id: \.self) { level in
                    FilterButton(
                        label: level.rawValue,
                        color: level.color,
                        isSelected: filter == level
                    ) {
                        filter = level
                    }
                }

                Spacer()

                // Actions
                Button {
                    entries.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Ocean.textDim)
                }
                .buttonStyle(.plain)
                .help("Clear logs")

                Button {
                    copyLogs()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(Ocean.textDim)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Ocean.surface)

            Divider().background(Ocean.border)

            // Log list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                            Divider().background(Ocean.border.opacity(0.3))
                        }
                    }
                }
                .onChange(of: entries.count) { _, _ in
                    if let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Ocean.bg)

            Divider().background(Ocean.border)

            // Footer
            HStack {
                Text("\(filteredEntries.count) entries")
                    .font(Ocean.mono(11))
                    .foregroundColor(Ocean.textDim)

                if filter != nil {
                    Text("(filtered)")
                        .font(Ocean.mono(11))
                        .foregroundColor(Ocean.textDim)
                }

                Spacer()

                Button {
                    refreshLogs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Refresh")
                            .font(Ocean.ui(11))
                    }
                    .foregroundColor(Ocean.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Ocean.surface)
        }
        .frame(width: 500, height: 400)
        .background(Ocean.bg)
        .onAppear {
            refreshLogs()
        }
    }

    private var filteredEntries: [LogEntry] {
        guard let filter = filter else { return entries }
        return entries.filter { $0.level == filter }
    }

    private func refreshLogs() {
        let logs = launcher.containerLogs
        entries = logs
            .split(separator: "\n")
            .compactMap { LogEntry.parse(String($0)) }
    }

    private func copyLogs() {
        let text = filteredEntries
            .map { "[\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Filter Button

private struct FilterButton: View {
    let label: String
    var color: Color = Ocean.textDim
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Ocean.ui(11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? color : Ocean.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? color.opacity(0.15) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Entry Row

public struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public init(entry: LogEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(Ocean.mono(10))
                .foregroundColor(Ocean.textDim)
                .frame(width: 60, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .font(Ocean.mono(9, weight: .medium))
                .foregroundColor(entry.level.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(entry.level.color.opacity(0.15))
                .cornerRadius(3)

            // Message
            Text(entry.message)
                .font(Ocean.mono(11))
                .foregroundColor(Ocean.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#if DEBUG
struct LogViewerView_Previews: PreviewProvider {
    static var previews: some View {
        LogViewerView(launcher: OpenClawLauncher())
    }
}
#endif
