# Cleankey Repository Structure

Last updated: 2026-08-17

## Project Overview

**Cleankey** is a macOS menu bar utility that temporarily disables all keyboard input system-wide, useful for cleaning a keyboard without triggering unwanted key presses.

- **Platform:** macOS 14.0+ (Sonoma and later)
- **Language:** Swift 5.0
- **UI Framework:** SwiftUI
- **Version:** 1.2.1 (`MARKETING_VERSION`)

---

## Repository Layout

```text
Cleankey/
├── .claude/                    (gitignored)
├── .git/
├── .gitignore
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── STRUCTURE.md
├── CleankeyDemo.gif
├── Cleankey.xcodeproj/
└── Cleankey/
    ├── Assets.xcassets/
    └── CleankeyApp.swift
```

### Key Files

- `AGENTS.md` / `CLAUDE.md` — Project instructions for AI coding assistants. Kept byte-identical apart from the title line; edit both together.
- `README.md` — Project overview and user-facing documentation.
- `STRUCTURE.md` — This file: repository structure and app architecture reference.
- `CleankeyDemo.gif` — Demo animation embedded in the README.
- `Cleankey.xcodeproj/` — Xcode project bundle.
- `Cleankey/CleankeyApp.swift` — Main SwiftUI app source (all code lives in this single file).
- `Cleankey/Assets.xcassets/` — App asset catalog (AppIcon, AccentColor).

There is no checked-in `Info.plist`. The target uses `GENERATE_INFOPLIST_FILE = YES`, so the Info.plist is produced at build time from `INFOPLIST_KEY_*` build settings.

`Releases/` is gitignored; release artifacts are not tracked.

---

## Code Architecture

All code lives in `Cleankey/CleankeyApp.swift` (~270 lines).

File-level constants: `appVersion` reads `CFBundleShortVersionString` from the bundle for the menu footer; `nxSysDefinedEventType` (14) and `nxAuxControlButtonsSubtype` (8) name the system-defined event magic numbers in one place, since they are needed both when building the event mask and when filtering in the callback.

### 1. `CleankeyApp` (SwiftUI App)
- **Type:** `@main struct` conforming to `App`
- **Purpose:** Main application entry point
- **Key Features:**
  - Uses `MenuBarExtra` for menu bar presence
  - Dynamic icon: `keyboard` (inactive) / `keyboard.fill` (active)
  - Menu bar UI with toggle switch, settings shortcuts, version, and quit button
  - 256pt fixed width menu
  - Window-style menu bar extra (`.menuBarExtraStyle(.window)`)
  - The switch binds through `blocker.setBlocking(_:)` rather than writing `isBlocking` directly
  - `.onAppear` requests Accessibility permission

### 2. `KeyboardBlocker` (ObservableObject)
- **Type:** `final class` conforming to `ObservableObject`
- **Purpose:** Core functionality — system-wide keyboard input blocking
- **Key Properties:**
  - `@Published private(set) var isBlocking: Bool` — Current blocking state, owned by the class so it can never report a lock that isn't installed
  - `private var eventTap: CFMachPort?` — Low-level event tap
  - `private var runLoopSource: CFRunLoopSource?` — Run loop integration
  - `@Published private(set) var failureMessage: String?` — Set when the tap cannot be created, surfaced inline in the menu; cleared on the next successful start

**Key Methods:**
- `setBlocking(_:)` — Single entry point for the switch; routes to `startBlocking()` / `stopBlocking()`.
- `startBlocking()` — Creates CGEvent tap at HID level, intercepts all keyboard events. Sets `isBlocking` to `true` only after the tap is installed; on failure (usually missing permissions) leaves it `false` and sets `failureMessage`.
- `teardownTap()` — Private. Removes the run loop source, disables and invalidates the tap, without touching published state so `deinit` can reuse it.
- `stopBlocking()` — Calls `teardownTap()` and sets `isBlocking` to `false`, restoring normal input.
- `requestAccessibilityPermissionIfNeeded()` — Prompts for Accessibility permissions via `AXIsProcessTrustedWithOptions`
- `eventTapCallback` — Static callback that filters events (blocks keys when active)

**Event Handling:**
- Blocks: Key down, key up, modifier flags, media keys (volume, brightness, play/pause)
- Uses `.cghidEventTap` for system-wide interception
- Returns `nil` to drop events, `Unmanaged.passUnretained(event)` to allow through
- Handles tap timeout/disable by re-enabling automatically
- Mouse events are never in the mask, so pointer input always keeps working — this is how the user toggles blocking back off

### 3. `AppDelegate` (NSApplicationDelegate)
- **Type:** `final class` conforming to `NSObject, NSApplicationDelegate`
- **Purpose:** App lifecycle management
- **Key Feature:** Sets activation policy to `.accessory` (no Dock icon, menu bar only), reinforcing the `LSUIElement` Info.plist key

### 4. `SystemSettingsOpener` (Utility Namespace)
- **Type:** `private enum` used as an uninstantiable namespace for static methods
- **Purpose:** Opens specific System Settings privacy panes
- **Supported Panes:**
  - `.inputMonitoring` — Input Monitoring settings
  - `.accessibility` — Accessibility settings
- **Implementation:** Opens `x-apple.systempreferences:com.apple.preference.security?<anchor>`, where the anchor is `Privacy_ListenEvent` for Input Monitoring and `Privacy_Accessibility` for Accessibility.
- **Anchor names matter:** there is no `Privacy_InputMonitoring` anchor — Input Monitoring is `Privacy_ListenEvent`. An unknown anchor does not fail; it silently opens the generic Privacy & Security page. `NSWorkspace.open()` returns `true` either way, so a bad anchor cannot be detected and no fallback chain is possible. Verify anchor names against `/System/Library/ExtensionKit/Extensions/SecurityPrivacyIntentsExtension.appex` before changing them.

### 5. `SettingsRow` (ViewModifier)
- **Type:** `private struct` conforming to `ViewModifier`
- **Purpose:** Shared look for the two settings rows — plain button style, full width, padding, and a hover highlight — so the modifier chain is not repeated per row
- **Style:** Rounded rectangle with 15% opacity secondary color on hover
- Applied via the `settingsRow()` helper in a `private extension View`

---

## Dependencies

### System Frameworks
- `SwiftUI` — UI framework
- `Cocoa` — macOS AppKit integration
- `ApplicationServices` — CGEvent and accessibility APIs
- `Combine` — Source of `ObservableObject` and `@Published`. The import is required: `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` stops SwiftUI from re-exporting them implicitly, so removing it breaks the build.

No third-party or package dependencies.

### Required Permissions
1. **Accessibility** — Required for CGEvent tap to function
2. **Input Monitoring** — Recommended for full keyboard interception

---

## UI Structure

```text
MenuBarExtra
└── VStack (8pt spacing, 8pt padding, 256pt width)
    ├── HStack — Title & Toggle
    │   ├── Text("Keyboard Cleaning")
    │   └── Toggle (switch style)
    ├── Text(failureMessage) — only when the tap failed to start
    ├── Divider
    ├── VStack — Settings Buttons (4pt spacing)
    │   ├── Button("Input Monitoring Settings…") [with hover effect]
    │   └── Button("Accessibility Settings…") [with hover effect]
    ├── Divider
    └── HStack — Footer
        ├── Text("v\(appVersion)")
        └── Button("Quit")
```

The footer version is read at runtime from the bundle's `CFBundleShortVersionString` via the file-level `appVersion` constant, so it tracks `MARKETING_VERSION` automatically.

---

## Features

### Implemented
- System-wide keyboard blocking (all keys + media keys)
- Menu bar toggle control
- Automatic permission requests
- Direct links to System Settings privacy panes
- Hover effects on menu items
- Auto-recovery from event tap timeouts
- Inline explanation in the menu when the event tap cannot be created (missing permissions)
- Menu bar-only presence (no Dock icon)

### Potential Future Enhancements
- Scheduled/timed blocking
- Keyboard shortcuts to toggle
- Block specific keys only
- Visual/audio feedback when blocking
- Launch at login option
- Persistent state (remember blocking state across launches)

---

## Technical Notes

### Event Tap Details
- **Tap Point:** `.cghidEventTap` (HID level, system-wide)
- **Insertion:** `.headInsertEventTap` (early in event pipeline)
- **Events Monitored:**
  - `CGEventType.keyDown` (bit 10)
  - `CGEventType.keyUp` (bit 11)
  - `CGEventType.flagsChanged` (bit 12)
  - NX_SYSDEFINED (bit 14) — for media keys
- **Media Key Handling:** Only blocks subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS)

### Memory Management
- Uses `Unmanaged` for passing Swift objects to C callbacks (`passUnretained` refcon)
- `stopBlocking()` removes the run loop source, disables the tap, and calls `CFMachPortInvalidate` so ports are not leaked across toggle cycles
- `deinit` calls `teardownTap()`, avoiding published-state mutation during deallocation
- Uses weak self references in async closures

---

## Build Configuration

- **Minimum Deployment Target:** macOS 14.0 (`MACOSX_DEPLOYMENT_TARGET`, mirrored to `LSMinimumSystemVersion`)
- **Supported Platforms:** `macosx` only (`SUPPORTS_MACCATALYST = NO`)
- **Architecture:** Universal (Apple Silicon + Intel)
- **Bundle Identifier:** `nick.Cleankey`
- **App Category:** Utilities
- **Activation Policy:** Accessory (menu bar only) — `INFOPLIST_KEY_LSUIElement = YES` plus the runtime `setActivationPolicy(.accessory)` call
- **Info.plist:** Generated (`GENERATE_INFOPLIST_FILE = YES`); configure via `INFOPLIST_KEY_*` settings, not a checked-in file
- **App Sandbox:** Enabled (`ENABLE_APP_SANDBOX = YES`), with `ENABLE_USER_SELECTED_FILES = NO`. The app opens no file pickers, so `com.apple.security.app-sandbox` is the only entitlement it needs.
- **Build number:** `CURRENT_PROJECT_VERSION` must be incremented on every release; it is the `CFBundleVersion` and does not track `MARKETING_VERSION`.
- **Platform settings:** the target is macOS-only. Do not reintroduce `INFOPLIST_KEY_UI*`, `IPHONEOS_DEPLOYMENT_TARGET`, `XROS_DEPLOYMENT_TARGET`, or `SUPPORTS_MACCATALYST` — Xcode adds them to multiplatform templates, but they are inert here.
- **Hardened Runtime:** Enabled
- **Code Signing:** Automatic, Apple Development, team `56JJ9GRL32`

### Building

Local development build:

```bash
xcodebuild -scheme Cleankey -configuration Release -destination 'platform=macOS' build
```

### Releasing

**Always archive — never ship a plain `build` output.**

```bash
xcodebuild -scheme Cleankey -configuration Release -destination 'platform=macOS' -archivePath ./Cleankey.xcarchive archive
```

Plain `xcodebuild build` injects `com.apple.security.get-task-allow` into the signed app (via the default `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`), regardless of configuration. That entitlement lets any process attach a debugger to the running app — unacceptable for an app that holds a system-wide keyboard event tap. Archiving strips it while keeping the sandbox entitlements.

Do **not** try to fix this by setting `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`; that suppresses the auto-generated entitlements wholesale and silently drops the App Sandbox too.

Verify before distributing:

```bash
codesign -d --entitlements - --xml Cleankey.xcarchive/Products/Applications/Cleankey.app | plutil -convert xml1 -o - -
```

Expected — sandbox present, no `get-task-allow`:

```text
com.apple.security.app-sandbox  true
```

The `1.2` build currently in `/Applications` was shipped with `get-task-allow` present and should be replaced.

---

## Current Issues

- None known.

---

## Version History

- **v1.2.1** (current)
- **v1.2** — Version present in the released `/Applications` build

---

## Notes for AI Assistants

- Read `README.md` and this file before starting any task; update both before committing (see `AGENTS.md` / `CLAUDE.md`)
- All code is currently in a single file (`Cleankey/CleankeyApp.swift`)
- Project uses modern SwiftUI patterns with Swift Concurrency support (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- Code follows Apple's Swift API design guidelines
- Private types are namespaced within the file
- View modifiers use custom extensions for reusability
