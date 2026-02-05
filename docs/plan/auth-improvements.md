# Authentication Improvements

## Current State

### OAuth Flow
1. User clicks "Sign in with Anthropic"
2. Browser opens to `claude.ai/oauth/authorize`
3. User authenticates on Anthropic website
4. User manually copies authorization code
5. User pastes code into app
6. App exchanges code for tokens

### Pain Points
- Manual copy-paste is error-prone
- Code format is `code#state` which users may not copy correctly
- No automatic callback handling

---

## 1. OAuth URL Scheme

### Problem
Users must manually copy the authorization code from the browser.

### Solution
Register a custom URL scheme (`openclaw://`) to receive OAuth callbacks automatically.

### Implementation

#### 1.1 Register URL Scheme

**File:** `app/macos/build.sh`

Update Info.plist generation to include:

```bash
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ... existing keys ... -->

    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>ai.openclaw.launcher</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>openclaw</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
```

#### 1.2 Handle URL Open Events

**File:** `app/macos/Sources/OpenClawApp/OpenClawApp.swift`

```swift
@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()

    var body: some Scene {
        WindowGroup {
            LauncherView(launcher: launcher)
                .onOpenURL { url in
                    handleOAuthCallback(url)
                }
        }
        // ... rest of scenes
    }

    private func handleOAuthCallback(_ url: URL) {
        // Expected: openclaw://callback?code=XXX&state=YYY
        guard url.scheme == "openclaw",
              url.host == "callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            return
        }

        Task {
            await launcher.handleOAuthCallback(code: code, state: state)
        }
    }
}
```

#### 1.3 Update OAuth Flow

**File:** `app/macos/Sources/OpenClawLib/AnthropicOAuth.swift`

Update redirect URI:
```swift
// Before
private static let redirectURI = "https://console.anthropic.com/oauth/callback"

// After
private static let redirectURI = "openclaw://callback"
```

Update authorization URL construction:
```swift
static func authorizationURL(codeChallenge: String, state: String) -> URL {
    var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
    components.queryItems = [
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "code_challenge", value: codeChallenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components.url!
}
```

#### 1.4 Add Callback Handler to Launcher

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

```swift
public func handleOAuthCallback(code: String, state: String) async {
    // Verify state matches what we generated
    guard state == self.oauthState else {
        addStep(.error, "OAuth state mismatch - possible CSRF attack")
        return
    }

    // Exchange code for token
    do {
        try await AnthropicOAuth.exchangeCode(code, verifier: self.codeVerifier)
        addStep(.done, "Signed in with Anthropic")
        self.state = .working
        await continueAfterAuth()
    } catch {
        addStep(.error, "OAuth exchange failed: \(error.localizedDescription)")
    }
}
```

#### 1.5 Store OAuth State

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

Add properties to track OAuth flow:
```swift
private var oauthState: String?
private var codeVerifier: String?

public func startOAuth() async {
    let (verifier, challenge) = AnthropicOAuth.generatePKCE()
    let state = UUID().uuidString

    self.codeVerifier = verifier
    self.oauthState = state

    let url = AnthropicOAuth.authorizationURL(
        codeChallenge: challenge,
        state: state
    )

    NSWorkspace.shared.open(url)
    addStep(.running, "Waiting for Anthropic sign-in...")
}
```

### Fallback: Keep Manual Code Entry

Keep the existing manual code entry as fallback:
- Some users may have browser isolation that blocks custom schemes
- Corporate environments may restrict URL scheme handling
- Edge case: user opens auth URL on different device

```swift
// In LauncherViews.swift
VStack {
    Text("Waiting for sign-in...")
    Text("If the browser didn't redirect back, paste the code below:")
        .font(.caption)
        .foregroundColor(.secondary)

    TextField("Authorization code", text: $manualCode)
    Button("Submit") {
        Task {
            await launcher.handleManualOAuthCode(manualCode)
        }
    }
}
```

### Testing

1. Build and install app
2. Click "Sign in with Anthropic"
3. Complete auth in browser
4. Verify browser redirects to `openclaw://callback?...`
5. Verify app receives callback and completes auth

**Note:** Custom URL schemes require app reinstall to register.

### Effort
Medium (2 hrs)

---

## 2. Token Refresh Improvements

### Current State
- Tokens refresh automatically on startup
- 5-minute buffer before actual expiry
- Banner shown if refresh fails

### Potential Improvements
- [ ] Background refresh (don't wait for startup)
- [ ] Push notification when token expires
- [ ] Longer refresh buffer (15 min)

### Effort
Low (30 min)

---

## 3. API Key Improvements

### Current State
- API key stored in `config/agents/default/agent/auth-profiles.json`
- chmod 600 for security
- No validation of key format

### Potential Improvements
- [ ] Validate `sk-ant-` prefix
- [ ] Test API key with simple request before saving
- [ ] Show masked key in UI (sk-ant-****-XXXX)

### Effort
Low (30 min)

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/macos/build.sh` | Add CFBundleURLTypes to Info.plist |
| `app/macos/Sources/OpenClawApp/OpenClawApp.swift` | Handle onOpenURL |
| `app/macos/Sources/OpenClawLib/AnthropicOAuth.swift` | Update redirect URI |
| `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift` | Add callback handler, store state |
| `app/macos/Sources/OpenClawLib/LauncherViews.swift` | Fallback manual entry UI |

---

## Dependencies

- Anthropic must support custom URL scheme redirects
- Test with actual Anthropic OAuth to verify scheme is accepted
- May need to register redirect URI with Anthropic if they validate it
