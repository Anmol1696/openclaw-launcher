# Testing Strategy for openclaw-launcher

## Overview

This document outlines a comprehensive testing strategy for the openclaw-launcher macOS SwiftUI app. The app manages Docker Desktop installation, container lifecycle, and OAuth authentication.

**Goal:** Ship v1.0 with confidence through a minimum viable test suite covering critical paths.

---

## 1. Unit Testing

### Setup for SwiftPM Package

**File Structure:**
```
openclaw-launcher/
├── Package.swift
├── Sources/
│   └── openclaw-launcher/
│       └── main.swift
└── Tests/
    └── openclaw-launcherTests/
        ├── DockerManagerTests.swift
        ├── OAuthTests.swift
        ├── ConfigTests.swift
        └── ShellExecutorTests.swift
```

**Package.swift** - Add test target:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "openclaw-launcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "openclaw-launcher", targets: ["openclaw-launcher"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(name: "openclaw-launcher"),
        .testTarget(
            name: "openclaw-launcherTests",
            dependencies: ["openclaw-launcher"]
        )
    ]
)
```

### Refactoring for Testability

**Problem:** A single 1300-line `main.swift` is hard to test.

**Solution:** Extract testable components while keeping the single-file structure if needed:

```swift
// MARK: - Testable Protocol Abstractions
protocol ShellExecutor {
    func run(_ command: String, args: [String]) -> Result<String, Error>
}

protocol DockerManager {
    func isInstalled() -> Bool
    func pullImage(_ image: String) -> Result<Void, Error>
    func runContainer(image: String, flags: [String]) -> Result<String, Error>
    func stopContainer(_ id: String) -> Result<Void, Error>
}

protocol ConfigWriter {
    func writeConfig(_ data: Data, to path: String) throws
    func readConfig(from path: String) throws -> Data
}

// MARK: - Real Implementations
struct RealShellExecutor: ShellExecutor {
    func run(_ command: String, args: [String]) -> Result<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                return .success(output)
            } else {
                return .failure(ShellError.commandFailed(status: process.terminationStatus, output: output))
            }
        } catch {
            return .failure(error)
        }
    }
}

enum ShellError: Error {
    case commandFailed(status: Int32, output: String)
}

// MARK: - Mock Implementations for Testing
class MockShellExecutor: ShellExecutor {
    var responses: [String: Result<String, Error>] = [:]
    var executedCommands: [(command: String, args: [String])] = []
    
    func run(_ command: String, args: [String]) -> Result<String, Error> {
        executedCommands.append((command, args))
        let key = "\(command) \(args.joined(separator: " "))"
        return responses[key] ?? .failure(ShellError.commandFailed(status: 1, output: "Not mocked"))
    }
}
```

### Testing Shell Execution

**ShellExecutorTests.swift:**
```swift
import XCTest
@testable import openclaw_launcher

final class ShellExecutorTests: XCTestCase {
    var mockExecutor: MockShellExecutor!
    
    override func setUp() {
        super.setUp()
        mockExecutor = MockShellExecutor()
    }
    
    func testDockerVersionCheck() {
        // Given
        mockExecutor.responses["/usr/local/bin/docker --version"] = 
            .success("Docker version 24.0.7, build afdd53b")
        
        let manager = DockerManager(executor: mockExecutor)
        
        // When
        let isInstalled = manager.isInstalled()
        
        // Then
        XCTAssertTrue(isInstalled)
        XCTAssertEqual(mockExecutor.executedCommands.count, 1)
        XCTAssertEqual(mockExecutor.executedCommands[0].command, "/usr/local/bin/docker")
    }
    
    func testDockerNotInstalled() {
        // Given
        mockExecutor.responses["/usr/local/bin/docker --version"] = 
            .failure(ShellError.commandFailed(status: 127, output: "command not found"))
        
        let manager = DockerManager(executor: mockExecutor)
        
        // When
        let isInstalled = manager.isInstalled()
        
        // Then
        XCTAssertFalse(isInstalled)
    }
    
    func testContainerStartup() throws {
        // Given
        mockExecutor.responses["/usr/local/bin/docker run -d --name openclaw ghcr.io/openclaw/openclaw:latest"] = 
            .success("abc123def456")
        
        let manager = DockerManager(executor: mockExecutor)
        
        // When
        let result = manager.runContainer(
            image: "ghcr.io/openclaw/openclaw:latest",
            flags: ["-d", "--name", "openclaw"]
        )
        
        // Then
        switch result {
        case .success(let containerId):
            XCTAssertEqual(containerId, "abc123def456")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}
```

### Testing OAuth PKCE Generation

**OAuthTests.swift:**
```swift
import XCTest
import CryptoKit
@testable import openclaw_launcher

final class OAuthTests: XCTestCase {
    
    func testCodeVerifierGeneration() {
        let oauth = OAuthManager()
        let verifier = oauth.generateCodeVerifier()
        
        // PKCE spec: 43-128 characters, base64url encoded
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        
        // Should only contain URL-safe characters
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        XCTAssertTrue(verifier.allSatisfy { char in
            allowedCharacters.contains(UnicodeScalar(String(char))!)
        })
    }
    
    func testCodeChallengeFromVerifier() {
        let oauth = OAuthManager()
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        
        let challenge = oauth.generateCodeChallenge(from: verifier)
        
        // Expected SHA256 hash of verifier, base64url encoded
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(challenge, expectedChallenge)
    }
    
    func testAuthURLConstruction() {
        let oauth = OAuthManager()
        let state = "randomstate123"
        let verifier = "testverifier"
        
        let url = oauth.buildAuthURL(state: state, codeVerifier: verifier)
        
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("code_challenge="))
        XCTAssertTrue(url!.absoluteString.contains("code_challenge_method=S256"))
        XCTAssertTrue(url!.absoluteString.contains("state=\(state)"))
    }
    
    func testTokenExchange() async throws {
        let mockHTTPClient = MockHTTPClient()
        mockHTTPClient.responses["/oauth/token"] = """
        {
            "access_token": "sk-ant-test123",
            "token_type": "Bearer",
            "expires_in": 3600
        }
        """
        
        let oauth = OAuthManager(httpClient: mockHTTPClient)
        let token = try await oauth.exchangeCodeForToken(
            code: "auth_code_123",
            verifier: "code_verifier_123"
        )
        
        XCTAssertEqual(token, "sk-ant-test123")
    }
}
```

### Testing Config Writing

**ConfigTests.swift:**
```swift
import XCTest
@testable import openclaw_launcher

final class ConfigTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testWriteConfig() throws {
        let writer = ConfigWriter()
        let configPath = tempDir.appendingPathComponent("config.json")
        
        let config = Config(
            apiKey: "sk-ant-test123",
            gatewayPort: 5080,
            dockerImage: "ghcr.io/openclaw/openclaw:latest"
        )
        
        let data = try JSONEncoder().encode(config)
        try writer.writeConfig(data, to: configPath.path)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        
        let readData = try Data(contentsOf: configPath)
        let readConfig = try JSONDecoder().decode(Config.self, from: readData)
        XCTAssertEqual(readConfig.apiKey, config.apiKey)
    }
    
    func testConfigPermissions() throws {
        let writer = ConfigWriter()
        let configPath = tempDir.appendingPathComponent("config.json")
        
        let data = "{}".data(using: .utf8)!
        try writer.writeConfig(data, to: configPath.path)
        
        // Config should be readable only by owner (600)
        let attrs = try FileManager.default.attributesOfItem(atPath: configPath.path)
        let permissions = attrs[.posixPermissions] as! Int
        XCTAssertEqual(permissions & 0o777, 0o600)
    }
}
```

### Running Unit Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter ConfigTests

# With verbose output
swift test --verbose

# Generate code coverage (requires Xcode)
swift test --enable-code-coverage
```

---

## 2. UI Testing

### SwiftUI Preview Testing

**Strategy:** Use previews for rapid visual iteration, not automated testing.

**Best Practices:**
- Create preview variants for different states:
  - Initial state (checking Docker)
  - Docker not installed
  - Docker installing
  - Container running
  - OAuth flow
  - Error states

**Example:**
```swift
#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(viewModel: .mockInitial)
                .previewDisplayName("Initial")
            
            ContentView(viewModel: .mockDockerMissing)
                .previewDisplayName("Docker Missing")
            
            ContentView(viewModel: .mockRunning)
                .previewDisplayName("Running")
            
            ContentView(viewModel: .mockError)
                .previewDisplayName("Error State")
        }
    }
}

extension LauncherViewModel {
    static var mockInitial: LauncherViewModel {
        let vm = LauncherViewModel(dockerManager: MockDockerManager())
        vm.status = "Checking Docker installation..."
        return vm
    }
    
    static var mockDockerMissing: LauncherViewModel {
        let vm = LauncherViewModel(dockerManager: MockDockerManager())
        vm.status = "Docker Desktop not found"
        vm.showInstallButton = true
        return vm
    }
}
#endif
```

### XCUITest Setup

**UITests/LauncherUITests.swift:**
```swift
import XCTest

final class LauncherUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Launch arguments to control app behavior
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "MOCK_DOCKER": "1",
            "SKIP_OAUTH": "1"
        ]
    }
    
    func testLaunchFlow() {
        app.launch()
        
        // Wait for initial screen
        let statusLabel = app.staticTexts["statusLabel"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))
        
        // Should show checking status
        XCTAssertTrue(statusLabel.label.contains("Checking"))
    }
    
    func testDockerInstallButton() {
        app.launchEnvironment["MOCK_DOCKER_MISSING"] = "1"
        app.launch()
        
        // Should show install button when Docker missing
        let installButton = app.buttons["Install Docker Desktop"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 5))
        
        installButton.tap()
        
        // Should navigate to installation flow
        let installingLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Installing'")).firstMatch
        XCTAssertTrue(installingLabel.waitForExistence(timeout: 2))
    }
    
    func testContainerStartStop() {
        app.launch()
        
        // Wait for container to start (mocked)
        let runningIndicator = app.images["statusGreen"]
        XCTAssertTrue(runningIndicator.waitForExistence(timeout: 10))
        
        // Find and tap stop button
        let stopButton = app.buttons["Stop"]
        stopButton.tap()
        
        // Should show stopped state
        let stoppedIndicator = app.images["statusRed"]
        XCTAssertTrue(stoppedIndicator.waitForExistence(timeout: 5))
        
        // Restart
        let startButton = app.buttons["Start"]
        startButton.tap()
        XCTAssertTrue(runningIndicator.waitForExistence(timeout: 10))
    }
    
    func testOAuthFlow() {
        app.launchEnvironment["MOCK_OAUTH_REQUIRED"] = "1"
        app.launch()
        
        // Should show OAuth prompt
        let oauthButton = app.buttons["Sign in with Anthropic"]
        XCTAssertTrue(oauthButton.waitForExistence(timeout: 5))
        
        oauthButton.tap()
        
        // In testing, mock the OAuth callback
        // In real testing, you'd need to handle browser interaction
        
        // Verify token stored
        let successLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Authenticated'")).firstMatch
        XCTAssertTrue(successLabel.waitForExistence(timeout: 5))
    }
}
```

### Snapshot Testing (Optional)

For visual regression testing, use [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing):

```swift
import SnapshotTesting
import XCTest
@testable import openclaw_launcher

final class SnapshotTests: XCTestCase {
    func testInitialView() {
        let view = ContentView(viewModel: .mockInitial)
        assertSnapshot(matching: view, as: .image(layout: .device(config: .Mac)))
    }
    
    func testErrorState() {
        let view = ContentView(viewModel: .mockError)
        assertSnapshot(matching: view, as: .image(layout: .device(config: .Mac)))
    }
}
```

**Trade-off:** Snapshot tests are thorough but brittle (break on any visual change). Only use for critical screens.

---

## 3. Integration Testing

### Docker Lifecycle Testing

**Challenge:** Integration tests need real Docker or sophisticated mocks.

**Approach:** Separate "real" integration tests that require Docker:

**Tests/IntegrationTests/DockerIntegrationTests.swift:**
```swift
import XCTest
@testable import openclaw_launcher

final class DockerIntegrationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        // Skip if Docker not available
        guard isDockerAvailable() else {
            throw XCTSkip("Docker not available")
        }
        
        // Clean up any existing test containers
        cleanupTestContainers()
    }
    
    override func tearDown() {
        cleanupTestContainers()
        super.tearDown()
    }
    
    func testPullImage() throws {
        let executor = RealShellExecutor()
        let manager = DockerManager(executor: executor)
        
        let result = manager.pullImage("hello-world")
        
        switch result {
        case .success:
            XCTAssertTrue(true)
        case .failure(let error):
            XCTFail("Failed to pull image: \(error)")
        }
    }
    
    func testContainerLifecycle() throws {
        let executor = RealShellExecutor()
        let manager = DockerManager(executor: executor)
        
        // Start container
        let startResult = manager.runContainer(
            image: "hello-world",
            flags: ["--name", "openclaw-test"]
        )
        
        guard case .success(let containerId) = startResult else {
            XCTFail("Failed to start container")
            return
        }
        
        XCTAssertFalse(containerId.isEmpty)
        
        // Stop container
        let stopResult = manager.stopContainer(containerId)
        XCTAssertTrue(stopResult.isSuccess)
        
        // Remove container
        let removeResult = executor.run("/usr/local/bin/docker", args: ["rm", containerId])
        XCTAssertTrue(removeResult.isSuccess)
    }
    
    func testHealthCheck() async throws {
        let executor = RealShellExecutor()
        let manager = DockerManager(executor: executor)
        
        // Start gateway container
        _ = try manager.runContainer(
            image: "ghcr.io/openclaw/openclaw:latest",
            flags: ["-d", "--name", "openclaw-test", "-p", "5080:5080"]
        )
        
        // Wait and poll health
        let checker = HealthChecker()
        let isHealthy = await checker.waitForHealthy(url: "http://localhost:5080/health", timeout: 30)
        
        XCTAssertTrue(isHealthy)
    }
    
    // Helper methods
    private func isDockerAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
        process.arguments = ["--version"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func cleanupTestContainers() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", "docker ps -a | grep openclaw-test | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true"]
        try? process.run()
        process.waitUntilExit()
    }
}
```

### First-Run vs Subsequent Runs

**Test Strategy:**
```swift
final class StateTests: XCTestCase {
    var tempConfigDir: URL!
    
    override func setUp() {
        super.setUp()
        tempConfigDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempConfigDir, withIntermediateDirectories: true)
    }
    
    func testFirstRun() {
        let launcher = Launcher(configDir: tempConfigDir)
        
        XCTAssertTrue(launcher.isFirstRun())
        XCTAssertNil(launcher.loadConfig())
    }
    
    func testSubsequentRun() throws {
        let launcher = Launcher(configDir: tempConfigDir)
        
        // Simulate first run completion
        try launcher.saveConfig(Config(apiKey: "test", gatewayPort: 5080))
        
        XCTAssertFalse(launcher.isFirstRun())
        XCTAssertNotNil(launcher.loadConfig())
    }
    
    func testMigration() throws {
        // Test config migration from old format
        let oldConfigPath = tempConfigDir.appendingPathComponent("config.json")
        let oldConfig = """
        {
            "api_key": "old-format"
        }
        """
        try oldConfig.write(to: oldConfigPath, atomically: true, encoding: .utf8)
        
        let launcher = Launcher(configDir: tempConfigDir)
        let config = launcher.loadConfig()
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.apiKey, "old-format")
    }
}
```

### Running Integration Tests

```bash
# Run only unit tests (fast)
swift test --filter "openclaw-launcherTests"

# Run integration tests (requires Docker)
swift test --filter "IntegrationTests"

# Run all tests
swift test
```

---

## 4. CI/CD Testing

### GitHub Actions Setup

**Key Facts:**
- ✅ GitHub Actions `macos-14` runners have Docker Desktop installed
- ✅ Docker is available via `/usr/local/bin/docker`
- ⚠️ Docker daemon must be started manually
- ⚠️ macOS runners are slower and more expensive than Linux

**.github/workflows/test.yml:**
```yaml
name: Test

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  test:
    runs-on: macos-14
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app
      
      - name: Swift version
        run: swift --version
      
      - name: Start Docker
        run: |
          # Docker Desktop is installed but not running
          open -a Docker
          
          # Wait for Docker to be ready
          echo "Waiting for Docker to start..."
          while ! docker info >/dev/null 2>&1; do
            sleep 1
          done
          echo "Docker is ready"
          
          docker --version
      
      - name: Run unit tests
        run: swift test --filter "openclaw-launcherTests"
      
      - name: Run integration tests
        run: swift test --filter "IntegrationTests"
        timeout-minutes: 10
      
      - name: Run UI tests
        run: swift test --filter "UITests"
        timeout-minutes: 5

  test-without-docker:
    runs-on: macos-14
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Test Docker-not-installed scenario
        run: |
          # Temporarily hide Docker to test fallback
          export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
          swift test --filter "testDockerNotInstalled"
```

### Building and Signing

**.github/workflows/build.yml:**
```yaml
name: Build

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Import signing certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
        run: |
          echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          
          security create-keychain -p "${{ secrets.KEYCHAIN_PASSWORD }}" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "${{ secrets.KEYCHAIN_PASSWORD }}" build.keychain
          
          security import certificate.p12 \
            -k build.keychain \
            -P "$CERTIFICATE_PASSWORD" \
            -T /usr/bin/codesign
          
          security set-key-partition-list \
            -S apple-tool:,apple: \
            -s -k "${{ secrets.KEYCHAIN_PASSWORD }}" \
            build.keychain
      
      - name: Build release binary
        run: |
          swift build -c release --arch arm64 --arch x86_64
          
          cp .build/apple/Products/Release/openclaw-launcher ./openclaw-launcher
      
      - name: Sign binary
        run: |
          codesign --sign "${{ secrets.SIGNING_IDENTITY }}" \
            --timestamp \
            --options runtime \
            --entitlements entitlements.plist \
            --force \
            openclaw-launcher
          
          # Verify signature
          codesign --verify --deep --strict --verbose=2 openclaw-launcher
      
      - name: Create app bundle (optional)
        run: |
          mkdir -p OpenClaw.app/Contents/MacOS
          mkdir -p OpenClaw.app/Contents/Resources
          
          cp openclaw-launcher OpenClaw.app/Contents/MacOS/
          cp Info.plist OpenClaw.app/Contents/
          cp icon.icns OpenClaw.app/Contents/Resources/
          
          codesign --sign "${{ secrets.SIGNING_IDENTITY }}" \
            --timestamp \
            --options runtime \
            --entitlements entitlements.plist \
            --force \
            --deep \
            OpenClaw.app
      
      - name: Create DMG
        run: |
          # Using create-dmg (install via Homebrew in CI)
          brew install create-dmg
          
          create-dmg \
            --volname "OpenClaw Launcher" \
            --volicon "icon.icns" \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 100 \
            --icon "OpenClaw.app" 200 190 \
            --hide-extension "OpenClaw.app" \
            --app-drop-link 600 185 \
            "OpenClaw-${{ github.ref_name }}.dmg" \
            "OpenClaw.app"
      
      - name: Notarize DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
        run: |
          # Submit for notarization
          xcrun notarytool submit "OpenClaw-${{ github.ref_name }}.dmg" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait
          
          # Staple ticket to DMG
          xcrun stapler staple "OpenClaw-${{ github.ref_name }}.dmg"
      
      - name: Upload DMG
        uses: actions/upload-artifact@v4
        with:
          name: openclaw-launcher-dmg
          path: OpenClaw-*.dmg
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: OpenClaw-*.dmg
          draft: true
```

### Required Secrets

In GitHub Settings → Secrets, add:
- `CERTIFICATE_BASE64` - Base64-encoded .p12 developer certificate
- `CERTIFICATE_PASSWORD` - Password for .p12 file
- `KEYCHAIN_PASSWORD` - Temporary keychain password
- `SIGNING_IDENTITY` - Certificate name (e.g., "Developer ID Application: Your Name")
- `APPLE_ID` - Apple ID for notarization
- `APPLE_APP_PASSWORD` - App-specific password
- `TEAM_ID` - Apple Developer Team ID

### Cost Optimization

macOS runners are ~10x more expensive than Linux. Optimize:

```yaml
# Only run full tests on main branch
on:
  push:
    branches: [main]
  pull_request:
    paths:
      - '**.swift'
      - 'Package.swift'

# Cache Swift build artifacts
- name: Cache Swift packages
  uses: actions/cache@v3
  with:
    path: .build
    key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.resolved') }}
```

---

## 5. Manual Testing Checklist

Before shipping v1.0, manually verify:

### Installation Testing
- [ ] First install on clean macOS 13.0+ system
- [ ] First install when Docker Desktop not installed
- [ ] First install when Docker Desktop already installed
- [ ] Reinstall over previous version
- [ ] Install from DMG mounts correctly
- [ ] App opens without "unidentified developer" warning (notarized)
- [ ] App requests necessary permissions (if any)

### Docker Integration
- [ ] Detects Docker Desktop correctly (installed/not installed)
- [ ] Installs Docker Desktop via download or prompt to download
- [ ] Waits for Docker daemon to start before proceeding
- [ ] Pulls `ghcr.io/openclaw/openclaw:latest` successfully
- [ ] Handles pull failures (network issues, disk space)
- [ ] Starts container with correct security flags
- [ ] Container starts and health check passes
- [ ] Stop button actually stops container
- [ ] Restart button works after stop
- [ ] Handles Docker Desktop quit/restart scenarios
- [ ] Shows meaningful error if Docker daemon dies

### OAuth Flow
- [ ] "Sign in with Anthropic" button opens default browser
- [ ] OAuth page loads in browser correctly
- [ ] User can authenticate and authorize
- [ ] Callback URL redirects back to app
- [ ] App receives authorization code
- [ ] Token exchange succeeds
- [ ] Token saved securely to config file
- [ ] Config file has 600 permissions (owner-only read/write)
- [ ] Subsequent launches use saved token
- [ ] Token refresh works (if implemented)
- [ ] Clear token / re-auth flow works

### UI/UX
- [ ] Status messages are clear and helpful
- [ ] Progress indicators work during long operations
- [ ] Error messages explain what went wrong
- [ ] Error messages suggest remediation
- [ ] App doesn't hang during Docker operations
- [ ] Can quit app cleanly at any stage
- [ ] Dock icon appears correctly
- [ ] Menu bar (if any) works

### Gateway Connection
- [ ] Health check polling starts after container up
- [ ] Health check succeeds within reasonable time
- [ ] App shows "Gateway Ready" or similar
- [ ] Connection info displayed (localhost:5080 or similar)
- [ ] Can open gateway URL in browser
- [ ] Gateway actually responds to requests

### Edge Cases
- [ ] Works on macOS 13.0 (minimum supported)
- [ ] Works on macOS 14.x (latest)
- [ ] Works on Apple Silicon (arm64)
- [ ] Works on Intel (x86_64)
- [ ] Low disk space handled gracefully
- [ ] No internet connection handled gracefully
- [ ] Port 5080 already in use handled gracefully
- [ ] App behavior when Docker Desktop updates
- [ ] Multiple launches of the app (don't start duplicate containers)

### Security
- [ ] Config file (with API key) has restrictive permissions
- [ ] No API key visible in UI or logs
- [ ] No secrets in crash reports
- [ ] Container runs with security restrictions (no privileged mode)
- [ ] App signed with Developer ID
- [ ] App notarized by Apple
- [ ] App requests only necessary entitlements

### Performance
- [ ] App launches in < 3 seconds
- [ ] Docker check completes in < 5 seconds
- [ ] Container starts in < 30 seconds (after image pulled)
- [ ] Health check polling doesn't peg CPU
- [ ] App uses < 100MB RAM when idle

### Cleanup
- [ ] Uninstall removes app cleanly
- [ ] Config files remain (or optionally cleaned)
- [ ] Docker image remains (or optionally cleaned)
- [ ] No orphaned processes

---

## Minimum Viable Test Suite

To ship v1.0 with confidence, prioritize:

### Must Have (Do not ship without):
1. **Unit tests for critical paths:**
   - OAuth PKCE generation and validation
   - Config file writing with correct permissions
   - Docker detection logic

2. **Manual testing:**
   - Complete installation checklist above
   - Test on both Apple Silicon and Intel
   - Test on both macOS 13 and 14

3. **CI/CD:**
   - Automated builds on tags
   - Code signing and notarization
   - DMG creation

### Nice to Have (Ship v1.1+):
1. Integration tests with real Docker
2. UI automation tests (XCUITest)
3. Snapshot testing
4. Automated update testing

### Test Execution Timeline

**Pre-commit:**
```bash
swift test --filter "openclaw-launcherTests"  # ~10 seconds
```

**Pre-push:**
```bash
swift test  # All tests ~2 minutes
```

**Pre-release:**
- Complete manual checklist
- Full CI/CD pipeline
- Test install on clean VM

---

## Tools and Resources

### Testing Libraries
- **XCTest** (built-in) - Unit and UI testing
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) - Visual regression testing
- [Nimble](https://github.com/Quick/Nimble) - Better assertions (optional)

### CI/CD Tools
- **GitHub Actions** - macos-14 runner
- [create-dmg](https://github.com/create-dmg/create-dmg) - DMG creation
- `xcrun notarytool` - Apple notarization
- `codesign` - Code signing

### Local Testing Tools
- Docker Desktop for Mac
- Xcode 15.2+
- Virtual machines (Parallels/VMware) for clean installs

### Debugging
```bash
# View detailed test output
swift test --verbose

# Run specific test
swift test --filter "testDockerInstalled"

# Debug test in Xcode
open Package.swift  # Opens in Xcode, then Cmd+U to test

# Check signing
codesign -dv --verbose=4 openclaw-launcher

# Check notarization
spctl -a -vv -t install openclaw-launcher.dmg
```

---

## Quick Start

1. **Set up tests:**
   ```bash
   mkdir -p Tests/openclaw-launcherTests
   touch Tests/openclaw-launcherTests/BasicTests.swift
   ```

2. **Run tests:**
   ```bash
   swift test
   ```

3. **Add CI:**
   ```bash
   mkdir -p .github/workflows
   # Copy test.yml example above
   ```

4. **Before v1.0 release:**
   - Complete manual testing checklist
   - Verify all CI jobs pass
   - Test DMG on clean machine

---

## Notes

- **Single-file refactoring:** You can keep the single `main.swift` structure by using `#if DEBUG` blocks for mock implementations and extracting testable protocol conformances.

- **Docker in CI:** GitHub Actions macOS runners have Docker Desktop installed but not running. You must start it with `open -a Docker` and wait for readiness.

- **Code signing:** Use `xcrun notarytool` (not legacy `altool`). It's faster and more reliable.

- **Test time:** macOS runners bill by the minute. Keep test suites lean.

---

**Ship with confidence by testing the paths that matter most: installation, Docker lifecycle, and OAuth.** Perfect coverage can wait for v1.1 — focus on the critical user journeys for v1.0.