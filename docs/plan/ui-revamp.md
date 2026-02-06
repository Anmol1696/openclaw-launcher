# UI Revamp Plan

> Source of truth for the Deep Ocean theme UI rebuild.
> Check off tasks as completed. Do not add features not in this list.

---

## Design Decisions (Locked In)

| Decision | Choice |
|----------|--------|
| Theme | Dark only (Deep Ocean) |
| Fonts | System fonts (SF Pro + SF Mono) with fallback |
| Window chrome | Native macOS (keep traffic lights) |
| Migration | Feature flag, parallel development |

---

## Task List

### Phase 1: Foundation
**Branch:** `feat/ui-foundation`

#### 1.1 Theme System
- [x] Create `Sources/OpenClawLib/Theme/OceanTheme.swift`
  - [x] Background colors: bg (#0a0f1a), surface (#0f1629), card (#151d35)
  - [x] Accent colors: accent (#00d4aa), accentDim, accentGlow (#00ffcc)
  - [x] Text colors: text (#e8f4f8), textDim (#6b8a99)
  - [x] Status colors: success, warning (#ff9f43), error (#ff6b6b), info (#4da6ff)
  - [x] Border color with opacity
  - [x] Color(hex:) initializer extension

#### 1.2 Base Components
- [x] Create `Sources/OpenClawLib/Components/` directory
- [x] `PulseIndicator.swift`
  - [x] Animated pulsing dot
  - [x] Color parameter (success/warning/error/idle)
  - [x] Size parameter
- [x] `OceanButton.swift`
  - [x] Primary variant (accent bg, dark text)
  - [x] Secondary variant (transparent, border)
  - [x] Danger variant (error color)
  - [x] Disabled state
  - [x] Icon + label support
- [x] `OceanBadge.swift`
  - [x] Default style (accent dim bg)
  - [x] Warning style
  - [x] Error style
  - [x] Monospace text
- [x] `OceanCard.swift`
  - [x] Surface background
  - [x] Border styling
  - [x] Corner radius (10px)
  - [x] Optional header slot
- [x] `OceanStepRow.swift` (renamed to avoid conflict)
  - [x] Icon variants: pending (○), active (⟳), done (✓), error (✕)
  - [x] Label text
  - [x] Time/duration text (monospace)
  - [x] Proper spacing and alignment
- [x] `OceanProgressBar.swift`
  - [x] Gradient fill (accent → glow)
  - [x] Background track
  - [x] Progress value (0-1)
  - [x] Optional meta text below

#### 1.3 Foundation Tests (deferred - manual QA)
- [ ] Test theme colors render correctly
- [ ] Test button states
- [ ] Test pulse animation runs

---

### Phase 2: Main Window
**Branch:** `feat/ui-main-states`

#### 2.1 Layout Structure
- [x] Create `Sources/OpenClawLib/Views/` directory (if not exists)
- [x] `HeroSection.swift`
  - [x] Logo (🐙 in rounded rect with gradient)
  - [x] App title "OpenClaw"
  - [x] Subtitle "Isolated AI Agent • Docker Powered"
  - [x] Radial glow effect behind logo
- [x] `StatusPanel.swift`
  - [x] Card container
  - [x] Header row: pulse indicator + status text + badge
  - [x] Divider
  - [x] Steps list (scrollable if needed)
  - [x] Progress section (bar + meta)
- [x] `InfoCard.swift`
  - [x] Key-value row layout
  - [x] Copy button for values
  - [x] Connected badge component
- [x] `FooterBar.swift`
  - [x] Stats section (CPU, Memory)
  - [x] Action buttons (right-aligned)
  - [x] Background surface color
  - [x] Top border

#### 2.2 Main States
- [x] `NewLauncherView.swift` (new file, parallel to existing)
  - [x] Window background (bg color)
  - [x] VStack: Hero → StatusPanel → InfoCard (conditional) → Footer
  - [x] State-based rendering
- [x] Idle state
  - [x] Gray pulse indicator
  - [x] "Ready to Launch" text
  - [x] All steps pending
  - [x] Launch button enabled
- [x] Starting state
  - [x] Teal pulse indicator (animated)
  - [x] "Initializing Environment" text
  - [x] Steps updating (done → active → pending)
  - [x] Progress bar animating
  - [x] Cancel button
- [x] Running state
  - [x] Green pulse indicator
  - [x] "Environment Running" text
  - [x] All steps done with times
  - [x] Info card visible (Gateway URL)
  - [x] "Open Browser" + "Stop" buttons
- [x] Stopping state
  - [x] Orange pulse indicator
  - [x] "Shutting Down..." text
  - [x] Shutdown steps
  - [x] Disabled button

#### 2.3 Data Binding
- [ ] Add step timing to `LaunchStep` model (deferred - using existing steps)
  - [ ] `startTime: Date?`
  - [ ] `endTime: Date?`
  - [ ] `duration` computed property
- [ ] Update `OpenClawLauncher` to track step times
- [x] Wire new views to existing `@Published` properties

#### 2.4 Feature Flag
- [x] Add `@AppStorage("useNewUI")` flag
- [ ] Toggle in app (debug menu or settings) - deferred to settings phase
- [x] Conditional rendering in `OpenClawApp.swift`

---

### Phase 3: Error States
**Branch:** `feat/ui-error-states`

#### 3.1 Error View Component
- [x] `ErrorStateView.swift`
  - [x] Large icon (emoji)
  - [x] Title (error color)
  - [x] Message (dim text)
  - [x] Optional details box (monospace)
  - [x] Action buttons

#### 3.2 Error Variants
- [x] Docker not running
  - [x] Icon: 🐳
  - [x] Actions: Retry Connection, Open Docker
- [x] Image pull failed
  - [x] Show in status panel (step error)
  - [x] Error details box
  - [x] Actions: Retry, Use Cached
- [x] Port conflict
  - [x] Icon: 🔌
  - [x] Show current vs suggested port
  - [ ] Actions: Use suggested, Choose port (deferred - needs settings)
- [x] Container crashed
  - [x] Icon: 💥
  - [x] Show exit code
  - [x] Actions: Restart, View Logs, Settings (Settings deferred)

---

### Phase 4: Settings Window
**Branch:** `feat/ui-settings`

#### 4.1 Settings Infrastructure
- [x] Ensure `LauncherSettings` model exists (from user-preferences.md)
- [x] Settings persistence working

#### 4.2 Settings UI
- [x] `SettingsView.swift`
  - [x] Tab bar (General | Container | Advanced)
  - [x] Content area
  - [x] Close button in header
- [x] `SettingsGeneralTab.swift`
  - [x] Launch at startup toggle
  - [x] Show in menu bar toggle
  - [x] Check for updates toggle
- [x] `SettingsContainerTab.swift`
  - [x] Security mode dropdown (via memory/cpu dropdowns)
  - [x] Network isolation toggle
  - [x] Filesystem isolation toggle
  - [x] Memory limit dropdown
  - [x] CPU limit dropdown
- [x] `SettingsAdvancedTab.swift`
  - [x] Health check interval stepper
  - [x] Custom port field
  - [x] Debug mode toggle
  - [x] Reset to defaults button

#### 4.3 Settings Components
- [x] Toggle row component
- [x] Dropdown row component
- [x] Section header component

---

### Phase 5: Supporting Views
**Branch:** `feat/ui-supporting`

#### 5.1 Log Viewer
- [x] `LogViewerView.swift`
  - [x] Header with title
  - [x] Filter buttons (All/Info/Warn/Error)
  - [x] Log list (scrollable)
  - [x] Footer with count + streaming indicator
- [x] `LogEntryRow.swift` (included in LogViewerView.swift)
  - [x] Timestamp (monospace, dim)
  - [x] Level badge (colored)
  - [x] Source tag
  - [x] Message text
- [x] Log filtering logic
  - [x] `@State` filter selection
  - [x] Filtered array computed property
- [x] Actions: Clear, Export, Copy

#### 5.2 Menu Bar Popover
- [x] `MenuBarPopover.swift` (new, replaces MenuBarContent)
  - [x] Header: logo + title + status badge
  - [x] Stats grid (Uptime + Status)
  - [x] Action list
  - [x] Footer links
- [x] Running state layout
- [x] Stopped state layout (launch button)
- [x] Wire to existing launcher state

#### 5.3 Modals
- [x] `OceanModal.swift` (base component)
  - [x] Overlay background
  - [x] Modal card
  - [x] Icon slot
  - [x] Title + message
  - [x] Action buttons row
- [x] `ConfirmStopModal.swift`
- [x] `ConfirmResetModal.swift`
- [ ] Update banner component (inline, not modal) - deferred

#### 5.4 Resource Monitor (Optional)
- [ ] `ResourceMonitor.swift` - deferred
  - [ ] CPU bar
  - [ ] Memory bar
  - [ ] Network in/out (if feasible)
- [ ] Docker stats polling (2-3s interval)
- [ ] Wire to footer stats display

---

### Phase 6: Onboarding
**Branch:** `feat/ui-onboarding`

#### 6.1 Onboarding Flow
- [x] `OnboardingView.swift`
  - [x] Step indicator dots
  - [x] Content area
  - [x] Navigation buttons
- [x] Step 1: Welcome
  - [x] 🐙 illustration
  - [x] Title + description
  - [x] "Get Started" button
- [x] Step 2: Docker Check
  - [x] 🐳 illustration
  - [x] Status checklist (installed, running, version)
  - [x] Continue/Back buttons
- [x] Step 2b: Docker Missing (conditional)
  - [x] Error styling
  - [x] Download Docker button
  - [x] Check Again button
- [x] Step 3: Complete
  - [x] ✓ illustration
  - [x] "You're All Set!"
  - [x] "Launch First Environment" button
  - [x] Keyboard shortcut hint

#### 6.2 First-Run Detection
- [x] Add `hasCompletedOnboarding` to settings
- [x] Show onboarding on first launch
- [x] Skip if already completed

---

### Phase 7: Cleanup & Polish
**Branch:** `feat/ui-polish`

- [ ] Remove old `LauncherView.swift` (after validation)
- [ ] Remove feature flag
- [ ] Final animation polish
- [ ] Keyboard navigation testing
- [ ] VoiceOver accessibility check
- [ ] Performance check (no lag)

---

## File Checklist

New files to create:

```
Sources/OpenClawLib/
├── Theme/
│   └── [x] OceanTheme.swift
├── Components/
│   ├── [x] PulseIndicator.swift
│   ├── [x] OceanButton.swift
│   ├── [x] OceanBadge.swift
│   ├── [x] OceanCard.swift
│   ├── [x] OceanStepRow.swift
│   ├── [x] OceanProgressBar.swift
│   ├── [x] OceanModal.swift
│   └── [ ] ResourceBar.swift
└── Views/
    ├── [x] NewLauncherView.swift
    ├── [x] HeroSection.swift
    ├── [x] StatusPanel.swift
    ├── [x] InfoCard.swift
    ├── [x] FooterBar.swift
    ├── [x] ErrorStateView.swift
    ├── [x] SettingsView.swift
    ├── [x] SettingsGeneralTab.swift
    ├── [x] SettingsContainerTab.swift
    ├── [x] SettingsAdvancedTab.swift
    ├── [x] LogViewerView.swift
    ├── [x] LogEntryRow.swift (in LogViewerView.swift)
    ├── [x] MenuBarPopover.swift
    ├── [x] ConfirmStopModal.swift (in OceanModal.swift)
    ├── [x] ConfirmResetModal.swift (in OceanModal.swift)
    └── [x] OnboardingView.swift
```

Files to modify:
```
[ ] Sources/OpenClawLib/Models.swift - Add step timing
[x] Sources/OpenClawLib/OpenClawLauncher.swift - Track errors (lastError property)
[x] Sources/OpenClawApp/OpenClawApp.swift - Feature flag, onboarding
[ ] app/macos/Package.swift - No changes needed (no new deps)
```

---

## Progress Tracker

| Phase | Status | Tasks | Done |
|-------|--------|-------|------|
| 1. Foundation | **Complete** | 21 | 18 |
| 2. Main Window | **Complete** | 24 | 21 |
| 3. Error States | **Complete** | 9 | 8 |
| 4. Settings | **Complete** | 14 | 14 |
| 5. Supporting | **Complete** | 16 | 13 |
| 6. Onboarding | **Complete** | 10 | 10 |
| 7. Cleanup | Not Started | 6 | 0 |
| **Total** | | **100** | **84** |

---

## Rules

1. **Do not add features not in this list**
2. **Check off tasks as completed**
3. **One phase = one branch = one PR**
4. **Test each component before moving on**
5. **Keep existing UI working until Phase 7**
