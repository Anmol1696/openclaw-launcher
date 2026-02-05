import XCTest
@testable import OpenClawLib

final class ConfigTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEnvFileRoundTrip() throws {
        let token = "abc123def456"
        let port = 18789
        let envContent = "OPENCLAW_GATEWAY_TOKEN=\(token)\nOPENCLAW_PORT=\(port)\n"

        let envFile = tempDir.appendingPathComponent(".env")
        try envContent.write(to: envFile, atomically: true, encoding: .utf8)

        // Parse it back
        let content = try String(contentsOf: envFile, encoding: .utf8)
        var parsedToken: String?
        for line in content.split(separator: "\n") {
            if line.hasPrefix("OPENCLAW_GATEWAY_TOKEN=") {
                parsedToken = String(line.dropFirst("OPENCLAW_GATEWAY_TOKEN=".count))
            }
        }

        XCTAssertEqual(parsedToken, token)
    }

    func testConfigJsonStructure() throws {
        let token = "testtoken123"
        let config = """
        {
          "gateway": {
            "mode": "local",
            "bind": "lan",
            "auth": {
              "mode": "token",
              "token": "\(token)"
            },
            "controlUi": {
              "enabled": true,
              "basePath": "/openclaw",
              "dangerouslyDisableDeviceAuth": true
            }
          },
          "agents": {
            "defaults": {
              "workspace": "/home/node/.openclaw/workspace",
              "model": { "primary": "anthropic/claude-opus-4-5" }
            }
          }
        }
        """

        let data = config.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let gateway = json["gateway"] as! [String: Any]
        XCTAssertEqual(gateway["mode"] as? String, "local")

        let auth = gateway["auth"] as! [String: Any]
        XCTAssertEqual(auth["token"] as? String, token)

        let controlUi = gateway["controlUi"] as! [String: Any]
        XCTAssertEqual(controlUi["enabled"] as? Bool, true)
        XCTAssertEqual(controlUi["basePath"] as? String, "/openclaw")

        let agents = json["agents"] as! [String: Any]
        XCTAssertNotNil(agents["defaults"])
    }

    // MARK: - LauncherSettings Tests

    func testSettingsDefaults() {
        let settings = LauncherSettings()
        XCTAssertEqual(settings.healthCheckInterval, 5.0)
        XCTAssertEqual(settings.openBrowserOnStart, true)
        XCTAssertEqual(settings.dockerImage, "ghcr.io/openclaw/openclaw:latest")
        XCTAssertEqual(settings.memoryLimit, "2g")
        XCTAssertEqual(settings.cpuLimit, 2.0)
        XCTAssertEqual(settings.port, 18789)
    }

    func testSettingsEncodeDecode() throws {
        let settings = LauncherSettings(
            healthCheckInterval: 10.0,
            openBrowserOnStart: false,
            dockerImage: "custom/image:v1",
            memoryLimit: "4g",
            cpuLimit: 4.0,
            port: 19000
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LauncherSettings.self, from: data)

        XCTAssertEqual(settings, decoded)
    }

    func testSettingsSaveLoad() throws {
        // Create custom settings
        var settings = LauncherSettings()
        settings.port = 12345
        settings.memoryLimit = "8g"

        // Save to temp file
        let settingsFile = tempDir.appendingPathComponent("settings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFile)

        // Load back
        let loadedData = try Data(contentsOf: settingsFile)
        let loaded = try JSONDecoder().decode(LauncherSettings.self, from: loadedData)

        XCTAssertEqual(loaded.port, 12345)
        XCTAssertEqual(loaded.memoryLimit, "8g")
    }

    func testMigration() throws {
        let oldDir = tempDir.appendingPathComponent("old-state")
        let newDir = tempDir.appendingPathComponent("new-state")

        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try "test".write(to: oldDir.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        // Simulate migration: move old → new if old exists and new doesn't
        if FileManager.default.fileExists(atPath: oldDir.path)
            && !FileManager.default.fileExists(atPath: newDir.path) {
            try FileManager.default.moveItem(at: oldDir, to: newDir)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: newDir.appendingPathComponent("marker").path))
    }
}
