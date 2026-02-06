import Foundation

/// User-configurable settings for OpenClaw Launcher
public class LauncherSettings: ObservableObject, Codable {
    // MARK: - General Settings
    @Published public var launchAtStartup: Bool = false
    @Published public var showInMenuBar: Bool = true
    @Published public var checkForUpdates: Bool = true

    // MARK: - Container Settings
    @Published public var memoryLimit: MemoryLimit = .twoGB
    @Published public var cpuLimit: CPULimit = .two
    @Published public var networkIsolation: Bool = true
    @Published public var filesystemIsolation: Bool = true

    // MARK: - Advanced Settings
    @Published public var healthCheckInterval: Double = 5.0
    @Published public var customPort: Int = 18789
    @Published public var debugMode: Bool = false

    // MARK: - Enums

    public enum MemoryLimit: String, Codable, CaseIterable {
        case oneGB = "1g"
        case twoGB = "2g"
        case fourGB = "4g"
        case eightGB = "8g"

        public var displayName: String {
            switch self {
            case .oneGB: return "1 GB"
            case .twoGB: return "2 GB"
            case .fourGB: return "4 GB"
            case .eightGB: return "8 GB"
            }
        }
    }

    public enum CPULimit: String, Codable, CaseIterable {
        case one = "1.0"
        case two = "2.0"
        case four = "4.0"
        case unlimited = "0"

        public var displayName: String {
            switch self {
            case .one: return "1 Core"
            case .two: return "2 Cores"
            case .four: return "4 Cores"
            case .unlimited: return "Unlimited"
            }
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case launchAtStartup, showInMenuBar, checkForUpdates
        case memoryLimit, cpuLimit, networkIsolation, filesystemIsolation
        case healthCheckInterval, customPort, debugMode
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtStartup = try container.decodeIfPresent(Bool.self, forKey: .launchAtStartup) ?? false
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        memoryLimit = try container.decodeIfPresent(MemoryLimit.self, forKey: .memoryLimit) ?? .twoGB
        cpuLimit = try container.decodeIfPresent(CPULimit.self, forKey: .cpuLimit) ?? .two
        networkIsolation = try container.decodeIfPresent(Bool.self, forKey: .networkIsolation) ?? true
        filesystemIsolation = try container.decodeIfPresent(Bool.self, forKey: .filesystemIsolation) ?? true
        healthCheckInterval = try container.decodeIfPresent(Double.self, forKey: .healthCheckInterval) ?? 5.0
        customPort = try container.decodeIfPresent(Int.self, forKey: .customPort) ?? 18789
        debugMode = try container.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(checkForUpdates, forKey: .checkForUpdates)
        try container.encode(memoryLimit, forKey: .memoryLimit)
        try container.encode(cpuLimit, forKey: .cpuLimit)
        try container.encode(networkIsolation, forKey: .networkIsolation)
        try container.encode(filesystemIsolation, forKey: .filesystemIsolation)
        try container.encode(healthCheckInterval, forKey: .healthCheckInterval)
        try container.encode(customPort, forKey: .customPort)
        try container.encode(debugMode, forKey: .debugMode)
    }

    // MARK: - Persistence

    private static let settingsURL: URL = {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".openclaw-launcher/settings.json")
    }()

    public static func load() -> LauncherSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data) else {
            return LauncherSettings()
        }
        return settings
    }

    public func save() {
        do {
            let data = try JSONEncoder().encode(self)
            let dir = LauncherSettings.settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: LauncherSettings.settingsURL)
        } catch {
            print("[Settings] Failed to save: \(error)")
        }
    }

    public func resetToDefaults() {
        launchAtStartup = false
        showInMenuBar = true
        checkForUpdates = true
        memoryLimit = .twoGB
        cpuLimit = .two
        networkIsolation = true
        filesystemIsolation = true
        healthCheckInterval = 5.0
        customPort = 18789
        debugMode = false
        save()
    }
}
