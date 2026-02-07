# Code Signing and Notarization

This document explains how to sign and notarize OpenClaw Launcher for distribution.

## Why Signing Matters

Without proper code signing:
- macOS Gatekeeper shows "Apple cannot check it for malicious software"
- Users must manually bypass security warnings
- Homebrew will reject unsigned casks (mandatory by September 2026)

## Prerequisites

1. **Apple Developer Program** ($99/year) - https://developer.apple.com/programs/
2. **Developer ID Application certificate** (created in Xcode after enrollment)

## Local Signing

### 1. Create Developer ID Certificate

After enrolling in Apple Developer Program:

1. Open Xcode → Settings → Accounts
2. Select your Apple ID
3. Click "Manage Certificates"
4. Click + → "Developer ID Application"

### 2. Build with Signing

```bash
# Find your identity
security find-identity -v -p codesigning

# Build with Developer ID
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
  cd app/macos && bash build.sh
```

### 3. Notarize (Optional for Local)

First, store credentials in keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build with notarization:

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
  cd app/macos && bash build.sh
```

### 4. Verify

```bash
# Check signature
codesign -dv --verbose=4 dist/OpenClawLauncher.app

# Check notarization
spctl --assess --type exec dist/OpenClawLauncher.app
# Should output: "accepted"

# Check stapled ticket
stapler validate dist/OpenClawLauncher.dmg
```

## CI/CD Signing (GitHub Actions)

### Required Secrets

| Secret | Description |
|--------|-------------|
| `MACOS_CERTIFICATE` | Base64-encoded .p12 certificate |
| `MACOS_CERTIFICATE_PWD` | Password for the .p12 file |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | App-specific password |
| `HOMEBREW_TAP_TOKEN` | GitHub PAT with repo access to `homebrew-openclaw-launcher` |

### How to Export Certificate

1. Open Keychain Access
2. Find "Developer ID Application: Your Name"
3. Right-click → Export
4. Save as .p12 with a password
5. Convert to base64:
   ```bash
   base64 -i certificate.p12 | pbcopy
   # Paste into GitHub secret
   ```

### How to Get App-Specific Password

1. Go to https://appleid.apple.com
2. Security → App-Specific Passwords → Generate
3. Name it "GitHub Actions" or similar
4. Copy the generated password

### How to Find Team ID

1. Go to https://developer.apple.com/account
2. Membership → Team ID

### How to Create Homebrew Tap Token

1. Go to https://github.com/settings/tokens
2. Generate new token (classic) or fine-grained token
3. For classic: select `repo` scope
4. For fine-grained: select `homebrew-openclaw-launcher` repo with read/write access
5. Copy the token and add as `HOMEBREW_TAP_TOKEN` secret

## Build Script Environment Variables

| Variable | Effect |
|----------|--------|
| `DEVELOPER_ID` | Identity for code signing (e.g., "Developer ID Application: Name (ID)") |
| `NOTARIZE` | Set to "1" to enable notarization |

If neither is set, the script uses ad-hoc signing (for local development).

## Troubleshooting

### "errSecInternalComponent"

Keychain is locked. Run:
```bash
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db
```

### "The signature is invalid"

Re-sign with `--force`:
```bash
codesign --force --deep --sign "$DEVELOPER_ID" --options runtime \
  --entitlements OpenClawLauncher.entitlements dist/OpenClawLauncher.app
```

### "Package not accepted"

Notarization failed. Check the log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"
```

Common issues:
- Missing hardened runtime flag (`--options runtime`)
- Unsigned nested bundles or frameworks
- Code using disallowed APIs
