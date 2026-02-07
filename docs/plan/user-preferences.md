# User Preferences & Settings

## Current State

- No user-configurable settings
- No keyboard shortcuts
- All behavior is hardcoded:
  - Health check interval: 5s
  - Gateway timeout: 30 attempts
  - Log lines: 300

---

## 1. Settings Persistence

### Problem
Users can't customize app behavior.

### Solution
Store preferences in `~/.openclaw-launcher/settings.json`.

### Implementation

#### 1.1 Settings Model

**File:** `app/macos/Sources/OpenClawLib/Models.swift`

```swift
public struct LauncherSettings: Codable, Equatable {
    // Health & Performance
    public var healthCheckInterval: TimeInterval = 5.0
    public var gatewayTimeoutAttempts: Int = 30

    // Behavior
    public var autoStartOnLogin: Bool = false
    public var showInDock: Bool = true
    public var openBrowserOnStart: Bool = true

    // Docker
    public var dockerImage: String = "ghcr.io/openclaw/openclaw:latest"
    public var memoryLimit: String = "2g"
    public var cpuLimit: Double = 2.0

    // Advanced
    public var debugMode: Bool = false
    public var customPort: Int = 18789

    public init() {}

    // Settings file path
    public static var filePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-launcher")
            .appendingPathComponent("settings.json")
    }

    public static func load() -> LauncherSettings {
        guard let data = try? Data(contentsOf: filePath),
              let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data)
        else {
            return LauncherSettings()
        }
        return settings
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.filePath)
    }
}
```

#### 1.2 Integrate with Launcher

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

```swift
@Published public var settings: LauncherSettings

public init(shellExecutor: ShellExecutor = ProcessShellExecutor()) {
    self.shellExecutor = shellExecutor
    self.settings = LauncherSettings.load()
    // ... existing init code
}

// Use settings in health check
private func startHealthCheck() {
    healthCheckTimer = Timer.scheduledTimer(
        withTimeInterval: settings.healthCheckInterval,
        repeats: true
    ) { [weak self] _ in
        Task { await self?.checkGatewayHealth() }
    }
}

// Save settings when changed
public func updateSettings(_ newSettings: LauncherSettings) {
    settings = newSettings
    do {
        try settings.save()
    } catch {
        addStep(.warning, "Failed to save settings: \(error.localizedDescription)")
    }
}
```

### Effort
Low (45 min)

---

## 2. Keyboard Shortcuts

### Problem
Power users expect standard macOS shortcuts.

### Solution
Add keyboard shortcuts to menu bar and window commands.

### Implementation

**File:** `app/macos/Sources/OpenClawLib/LauncherViews.swift`

```swift
struct MenuBarContent: View {
    @ObservedObject var launcher: OpenClawLauncher
    @Binding var showLogs: Bool
    @Binding var showWindow: Bool

    var body: some View {
        Group {
            Button("Open Control UI") {
                launcher.openBrowser()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(launcher.state != .running)

            Divider()

            Button("Restart Container") {
                Task { await launcher.restartContainer() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(launcher.state != .running && launcher.state != .error)

            Button("Stop Container") {
                Task { await launcher.stopContainer() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(launcher.state != .running)

            Divider()

            Button("View Logs") {
                showLogs = true
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Show Window") {
                showWindow = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("1", modifiers: .command)

            Divider()

            Button("Settings...") {
                // Open settings window
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
```

### Shortcut Summary

| Shortcut | Action |
|----------|--------|
| `Cmd+O` | Open Control UI |
| `Cmd+R` | Restart Container |
| `Cmd+.` | Stop Container |
| `Cmd+L` | View Logs |
| `Cmd+1` | Show Window |
| `Cmd+,` | Settings |
| `Cmd+Q` | Quit |

### Effort
Low (15 min)

---

## 3. Settings UI (Deferred to UI Revamp)

### Design
Settings window with sections:

```
┌─────────────────────────────────────────────┐
│ Settings                              [x]   │
├─────────────────────────────────────────────┤
│                                             │
│ General                                     │
│ ┌─────────────────────────────────────────┐ │
│ │ □ Launch at login                       │ │
│ │ □ Show in Dock                          │ │
│ │ □ Open browser when ready               │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Docker                                      │
│ ┌─────────────────────────────────────────┐ │
│ │ Image: [ghcr.io/openclaw/openclaw:lat▼] │ │
│ │ Memory: [2g          ]                  │ │
│ │ CPUs:   [2.0         ]                  │ │
│ │ Port:   [18789       ]                  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Advanced                                    │
│ ┌─────────────────────────────────────────┐ │
│ │ Health check interval: [5   ] seconds  │ │
│ │ □ Debug mode                            │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│               [Reset to Defaults] [Save]    │
└─────────────────────────────────────────────┘
```

### Implementation (UI Revamp)

```swift
struct SettingsView: View {
    @ObservedObject var launcher: OpenClawLauncher
    @State private var settings: LauncherSettings

    init(launcher: OpenClawLauncher) {
        self.launcher = launcher
        self._settings = State(initialValue: launcher.settings)
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.autoStartOnLogin)
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Toggle("Open browser when ready", isOn: $settings.openBrowserOnStart)
            }

            Section("Docker") {
                TextField("Image", text: $settings.dockerImage)
                TextField("Memory limit", text: $settings.memoryLimit)
                Stepper("CPUs: \(settings.cpuLimit, specifier: "%.1f")",
                        value: $settings.cpuLimit, in: 0.5...8.0, step: 0.5)
                Stepper("Port: \(settings.customPort)",
                        value: $settings.customPort, in: 1024...65535)
            }

            Section("Advanced") {
                Stepper("Health check: \(Int(settings.healthCheckInterval))s",
                        value: $settings.healthCheckInterval, in: 1...60)
                Toggle("Debug mode", isOn: $settings.debugMode)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") {
                    settings = LauncherSettings()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    launcher.updateSettings(settings)
                }
            }
        }
    }
}
```

### Effort
Medium (part of UI revamp)

---

## 4. Launch at Login

### Implementation

Use `SMAppService` (macOS 13+):

```swift
import ServiceManagement

extension LauncherSettings {
    public func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if autoStartOnLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    public static var isRegisteredForLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

### Effort
Low (30 min)

---

## 5. Hide from Dock (LSUIElement)

### Implementation

To allow hiding from Dock, need to dynamically set `LSUIElement`:

```swift
extension LauncherSettings {
    public func applyShowInDock() {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
```

**Note:** Changing activation policy at runtime can be buggy. Better to:
1. Keep `LSUIElement = false` in Info.plist
2. Only allow this setting via restart

### Effort
Low (15 min)

---

## Implementation Order

| Phase | Items | Effort |
|-------|-------|--------|
| 1 | Keyboard Shortcuts | 15 min |
| 2 | Settings Model + Persistence | 45 min |
| 3 | Launch at Login | 30 min |
| 4 | Settings UI | Part of revamp |

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/macos/Sources/OpenClawLib/Models.swift` | Add LauncherSettings |
| `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift` | Load/save settings |
| `app/macos/Sources/OpenClawLib/LauncherViews.swift` | Keyboard shortcuts, settings UI |

---

## Settings File Example

`~/.openclaw-launcher/settings.json`:

```json
{
  "autoStartOnLogin": false,
  "cpuLimit": 2.0,
  "customPort": 18789,
  "debugMode": false,
  "dockerImage": "ghcr.io/openclaw/openclaw:latest",
  "gatewayTimeoutAttempts": 30,
  "healthCheckInterval": 5.0,
  "memoryLimit": "2g",
  "openBrowserOnStart": true,
  "showInDock": true
}
```
