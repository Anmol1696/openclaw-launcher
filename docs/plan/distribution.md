# Distribution Improvements

## Current State

| Asset | Signed? | Notarized? | Auto-Update? |
|-------|---------|------------|--------------|
| `.app` | Yes (Developer ID) | Pending | No |
| `.dmg` | No | N/A | No |

Users must run `xattr -cr OpenClawLauncher.app` to bypass Gatekeeper.

---

## 1. DMG Signing

### Problem
DMG is not code-signed. While notarization checks contents, signing the DMG provides complete chain of trust.

### Solution
Add codesign after DMG creation in `build.sh`.

### Implementation

**File:** `app/macos/build.sh`

After line 131 (`[ -f "$DMG_PATH" ] && echo "   ✅ DMG created"`), add:

```bash
# Sign DMG if Developer ID is available
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "   Signing DMG..."
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
    echo "   ✅ DMG signed"
fi
```

### Verification
```bash
codesign -vvv --deep --strict dist/OpenClawLauncher.dmg
```

### Effort
Low (15 min)

---

## 2. Auto-Updates via Sparkle

### Problem
Users must manually download new DMGs to update.

### Solution
Integrate Sparkle 2 framework for automatic updates.

### Implementation

#### 2.1 Add Sparkle Dependency

**File:** `app/macos/Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
],
targets: [
    .executableTarget(
        name: "OpenClawLauncher",
        dependencies: [
            "OpenClawLib",
            .product(name: "Sparkle", package: "Sparkle")
        ]
    ),
]
```

#### 2.2 Add Updater Controller

**File:** `app/macos/Sources/OpenClawApp/OpenClawApp.swift`

```swift
import Sparkle

@main
struct OpenClawApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        // ... existing code ...

        Settings {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            checkForUpdatesViewModel.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
```

#### 2.3 Add to Menu Bar

**File:** `app/macos/Sources/OpenClawLib/LauncherViews.swift`

In `MenuBarContent`:
```swift
Button("Check for Updates...") {
    // Trigger update check
}
.keyboardShortcut("u", modifiers: [.command, .shift])

Divider()
```

#### 2.4 Configure Info.plist

**File:** `app/macos/build.sh`

Add to Info.plist generation:
```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/constructive-io/openclaw-launcher/main/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>YOUR_ED25519_PUBLIC_KEY</string>
```

#### 2.5 Create Appcast

**File:** `appcast.xml` (repo root)

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>OpenClaw Launcher</title>
    <link>https://github.com/constructive-io/openclaw-launcher</link>
    <description>OpenClaw Launcher Updates</description>
    <language>en</language>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>1.0.0</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <pubDate>Mon, 03 Feb 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/constructive-io/openclaw-launcher/releases/download/v1.0.0/OpenClawLauncher.dmg"
        sparkle:edSignature="SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

#### 2.6 CI Integration

**File:** `.github/workflows/publish.yml`

Add step after release creation:
```yaml
- name: Update appcast
  run: |
    # Generate Sparkle signature
    # Update appcast.xml with new version
    # Commit and push appcast.xml
```

### Sparkle Key Generation
```bash
# Generate EdDSA key pair (one-time setup)
./bin/generate_keys
# Store private key securely, add public key to Info.plist
```

### Effort
Medium-High (3-4 hrs)

---

## 3. Homebrew Cask

### Current State
Tap exists at `constructive-io/homebrew-openclaw-launcher` and is auto-updated by CI.

### Usage
```bash
brew tap constructive-io/openclaw-launcher
brew install --cask openclaw-launcher
```

### CI Integration
Already implemented in `publish.yml` - updates cask on release.

### Improvements Needed
- [ ] Add `brew upgrade` support (requires proper versioning)
- [ ] Add `brew reinstall` for clean installs
- [ ] Consider quarantine attribute handling

---

## 4. Notarization

### Current Status
Submissions stuck "In Progress" for 24+ hours (Apple server issues).

### When to Retry
- Wait for Apple's notarization servers to stabilize
- Check status: `xcrun notarytool history --keychain-profile "AC_PASSWORD"`

### Verification After Success
```bash
# Mount DMG and verify app
hdiutil attach dist/OpenClawLauncher.dmg -mountpoint /tmp/dmg
spctl -a -vvv -t install /tmp/dmg/OpenClawLauncher.app
hdiutil detach /tmp/dmg
```

---

## Implementation Order

1. **DMG Signing** - Quick win, improves trust
2. **Wait for Notarization** - Apple dependency
3. **Sparkle Integration** - After notarization works
4. **Appcast Automation** - Part of Sparkle rollout

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/macos/build.sh` | DMG signing, Info.plist updates |
| `app/macos/Package.swift` | Add Sparkle dependency |
| `app/macos/Sources/OpenClawApp/OpenClawApp.swift` | Updater controller |
| `app/macos/Sources/OpenClawLib/LauncherViews.swift` | Menu item |
| `.github/workflows/publish.yml` | Appcast generation |
| `appcast.xml` (new) | Update feed |
