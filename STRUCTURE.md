# Cleankey Repository Structure

Last updated: 2026-08-18

## Project Overview

**Cleankey** is a macOS menu bar utility that temporarily disables all keyboard input system-wide, useful for cleaning a keyboard without triggering unwanted key presses.

- **Platform:** macOS 14.0+ (Sonoma and later)
- **Language:** Swift 5.0
- **UI Framework:** SwiftUI
- **Version:** 1.0 (`MARKETING_VERSION`), build 5 (`CURRENT_PROJECT_VERSION`)

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
├── ExportOptions.plist
├── .github/
│   └── workflows/
│       └── release.yml
├── Cleankey.xcodeproj/
└── Cleankey/
    ├── Assets.xcassets/
    └── CleankeyApp.swift
```

### Key Files

- `AGENTS.md` / `CLAUDE.md`: project instructions for AI coding assistants. Kept byte-identical apart from the title line; edit both together.
- `README.md`: Project overview and user-facing documentation.
- `STRUCTURE.md`: This file: repository structure and app architecture reference.
- `CleankeyDemo.gif`: Demo animation embedded in the README.
- `ExportOptions.plist`: Developer ID export settings used by `xcodebuild -exportArchive`. Contains no secrets.
- `.github/workflows/release.yml`: builds, signs, notarizes and publishes on a `v*` tag. Mirrors the manual steps below, so change both together.
- `Cleankey.xcodeproj/`: Xcode project bundle.
- `Cleankey/CleankeyApp.swift`: Main SwiftUI app source (all code lives in this single file).
- `Cleankey/Assets.xcassets/`: App asset catalog (AppIcon, AccentColor).

There is no checked-in `Info.plist`. The target uses `GENERATE_INFOPLIST_FILE = YES`, so the Info.plist is produced at build time from `INFOPLIST_KEY_*` build settings.

`Releases/` is gitignored; release artifacts are not tracked.

---

## Code Architecture

All code lives in `Cleankey/CleankeyApp.swift` (~472 lines).

`accessibilityPaneName` returns the System Settings label for the Accessibility
pane. macOS renamed it to "Device Control and Data Access"; confirmed on macOS 27
by reading `SecurityPrivacyExtension.appex`'s own localization table (key
`ACCESSIBILITY`). The release that introduced the rename is unconfirmed, so the
`#available(macOS 26, *)` boundary is an estimate. Correct it if a 26.x machine
still shows "Accessibility".

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
  - `.onAppear` requests both permissions

### 2. `KeyboardBlocker` (ObservableObject)
- **Type:** `final class` conforming to `ObservableObject`
- **Purpose:** core functionality, system-wide keyboard input blocking
- **Key Properties:**
  - `@Published private(set) var isBlocking: Bool`: Current blocking state, owned by the class so it can never report a lock that isn't installed
  - `private var eventTap: CFMachPort?`: Low-level event tap
  - `private var runLoopSource: CFRunLoopSource?`: Run loop integration
  - `@Published private(set) var failureMessage: String?`: Set when the tap cannot be created, surfaced inline in the menu; cleared on the next successful start

**Key Methods:**
- `setBlocking(_:)`: Single entry point for the switch; routes to `startBlocking()` / `stopBlocking()`.
- `startBlocking()`: Creates CGEvent tap at HID level, intercepts all keyboard events. Sets `isBlocking` to `true` only after the tap is installed; on failure (usually missing permissions) leaves it `false` and sets `failureMessage`.
- `teardownTap()`: Private. Removes the run loop source, disables and invalidates the tap, without touching published state so `deinit` can reuse it.
- `stopBlocking()`: Calls `teardownTap()` and sets `isBlocking` to `false`, restoring normal input.
- `requestPermissionsIfNeeded()`: Prompts for both privileges: Accessibility via `AXIsProcessTrustedWithOptions`, Input Monitoring via `CGRequestListenEventAccess()`. Neither takes effect until the app is relaunched.
- `missingPermissions`: Private. Reports which privileges are absent, via `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()`, so the failure message can name the actual cause rather than guess.
- `eventTapCallback`: Static callback that filters events (blocks keys when active)

**Event Handling:**
- Blocks: Key down, key up, modifier flags, media keys (volume, brightness, play/pause)
- Uses `.cghidEventTap` for system-wide interception
- Returns `nil` to drop events, `Unmanaged.passUnretained(event)` to allow through
- Handles tap timeout/disable by re-enabling automatically
- Mouse events are never in the mask, so pointer input always keeps working. That is how the user toggles blocking back off

### 3. `AppDelegate` (NSApplicationDelegate)
- **Type:** `final class` conforming to `NSObject, NSApplicationDelegate`
- **Purpose:** App lifecycle management
- **Key Feature:** Sets activation policy to `.accessory` (no Dock icon, menu bar only), reinforcing the `LSUIElement` Info.plist key

### 4. `SystemSettingsOpener` (Utility Namespace)
- **Type:** `private enum` used as an uninstantiable namespace for static methods
- **Purpose:** Opens specific System Settings privacy panes
- **Supported Panes:**
  - `.inputMonitoring`: Input Monitoring settings
  - `.accessibility`: Accessibility settings
- **Implementation:** Opens `x-apple.systempreferences:com.apple.preference.security?<anchor>`, where the anchor is `Privacy_ListenEvent` for Input Monitoring and `Privacy_Accessibility` for Accessibility.
- **Anchor names matter:** there is no `Privacy_InputMonitoring` anchor. Input Monitoring is `Privacy_ListenEvent`. An unknown anchor does not fail; it silently opens the generic Privacy & Security page. `NSWorkspace.open()` returns `true` either way, so a bad anchor cannot be detected and no fallback chain is possible. Verify anchor names against `/System/Library/ExtensionKit/Extensions/SecurityPrivacyIntentsExtension.appex` before changing them.

### 5. `UpdateChecker` (ObservableObject)
- **Purpose:** Compares the running version against the latest GitHub release
- **Endpoint:** `https://api.github.com/repos/seafyre/Cleankey/releases/latest`, reading `tag_name` and stripping a leading `v` (release tags are `v1.2.1` style)
- **Comparison:** `compare(_:options: .numeric)` so 1.10 sorts above 1.9
- **State machine:** `.idle` / `.checking` / `.upToDate` / `.available(String)` / `.failed`. The row's label *is* the state, so there is no separate status line, and `act()` downloads when an update is waiting and re-checks otherwise, so the up-to-date and failed states double as retry.
- `reset()` runs on panel appearance so a stale result doesn't linger as the label.
- **Installs nothing by design.** The user downloads and replaces the app. Adopting Sparkle would require bundling XPC services, `SUEnableInstallerLauncherService`, re-signing every nested binary with Developer ID, and publishing a signed appcast per release. That is too much machinery for an app that ships a few times a year.

### 6. `LoginItem` (ObservableObject)
- **Purpose:** Wraps `SMAppService.mainApp` for the Open at Login switch
- `refresh()` reads live status on every panel appearance, since the user can change it in System Settings
- Handles `.requiresApproval`. The user has switched Cleankey off in System Settings › General › Login Items, which the app cannot override, so it says so rather than failing silently

### 7. View components
- `ToggleRow`: titled switch row used by both toggles. `.controlSize(.small)`; SwiftUI's default `.regular` switch is oversized for a menu bar panel.
- `HintText`: secondary explanatory line under a row
- `HoverHighlight`: rounded hover highlight, shared by the settings rows **and** Quit
- `SettingsRow`: `HoverHighlight` plus plain button style and full-width leading alignment. Quit uses `hoverHighlight()` directly, since it sits right-aligned in the footer; that split is why the two are separate modifiers.

---

## Dependencies

### System Frameworks
- `SwiftUI`: UI framework
- `Cocoa`: macOS AppKit integration
- `ApplicationServices`: CGEvent and accessibility APIs
- `ServiceManagement`: `SMAppService` for the login item
- `Combine`: Source of `ObservableObject` and `@Published`. The import is required: `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` stops SwiftUI from re-exporting them implicitly, so removing it breaks the build.

No third-party or package dependencies.

### Required Permissions

Both are **required**. Verified empirically on 2026-08-17 by revoking each in turn:
with either one missing, the tap does not suppress input.

1. **Accessibility** (`kTCCServiceAccessibility`): Required to create a suppressing
   event tap. A `listenOnly` tap needs only Input Monitoring, but cannot drop events,
   so it is useless here.
2. **Input Monitoring** (`kTCCServiceListenEvent`): Required for `CGEventTap` to
   receive keyboard events at all.

Do not "simplify" the menu by removing either settings shortcut; neither permission
is optional.

Both are requested explicitly at first menu appearance. Granting either does **not**
affect the running process. macOS applies the change only on relaunch, so the first
toggle after granting will still fail. The failure message distinguishes the two
cases: a named missing privilege versus "Quit and reopen Cleankey", which is what a
grant-pending-relaunch looks like.

### Distribution: Developer ID, not the Mac App Store

Mac App Store submission is not a realistic path. App Review rejects apps under
Guideline 2.4.5 for using Accessibility features for non-accessibility purposes, and
suppressing keyboard input requires exactly that privilege. There is no engineering
workaround: `listenOnly` taps cannot drop events, and the IOKit HID routes that could
seize the keyboard are unavailable to a sandboxed app. Blocking all keyboard input is
inherently privileged, so the capability under objection is the app's entire purpose.

Ship via Developer ID + notarization (see Releasing below).

#### Alternative considered and declined (2026-08-17)

A permission-free design exists: instead of tapping events globally, present a
full-screen borderless window that takes key status and discards every key event,
combined with the kiosk `NSApplicationPresentationOptions`
(`DisableProcessSwitching`, `DisableForceQuit`, `DisableSessionTermination`; each
requires `HideDock` or `AutoHideDock` alongside it). An app is always allowed to
receive events routed to itself, so this needs no TCC permission and would make the
Mac App Store viable again.

It was declined because it is strictly weaker. It covers the screen rather than
locking invisibly in the background, and system hotkeys dispatched before app
delivery are expected to still fire: Spotlight, screenshot shortcuts, and the media
and brightness keys this app deliberately catches. Blocking the top row is a
core feature, so the trade was not worth it.

Do not re-investigate the permission split: `CGEventTap` in `.listenOnly` mode needs
only Input Monitoring, but cannot drop events. Suppression via `.defaultTap` requires
Accessibility. Verified empirically, and consistent with Apple DTS guidance in
developer.apple.com/forums/thread/707680.

---

## UI Structure

```text
MenuBarExtra
└── VStack (8pt spacing, 8pt padding, 256pt width)
    ├── ToggleRow("Keyboard Cleaning")
    ├── HintText(failureMessage), only when the tap failed to start
    ├── Divider
    ├── ToggleRow("Open at Login")
    ├── HintText(loginItem.message), only when approval is required
    ├── Divider
    ├── VStack, Settings Buttons (4pt spacing)
    │   ├── Button("Input Monitoring…") [hover]
    │   └── Button("<accessibilityPaneName>…") [hover]
    ├── Divider
    ├── Button(updates.title) [hover], label reflects update state
    ├── Divider
    └── HStack, Footer
        ├── Text("v\(appVersion)")
        └── Button("Quit") [hover]
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
- Open at Login, via `SMAppService`
- Check for Updates against GitHub Releases (notifies only; does not install)
- Auto-recovery from event tap timeouts
- Inline explanation in the menu when the event tap cannot be created (missing permissions)
- Menu bar-only presence (no Dock icon)

### Potential Future Enhancements
- Scheduled/timed blocking
- Keyboard shortcuts to toggle
- Block specific keys only
- Visual/audio feedback when blocking
- Persistent state (remember blocking state across launches)
- Automatic update check at launch (currently on demand only)

---

## Technical Notes

### Event Tap Details
- **Tap Point:** `.cghidEventTap` (HID level, system-wide)
- **Insertion:** `.headInsertEventTap` (early in event pipeline)
- **Events Monitored:**
  - `CGEventType.keyDown` (bit 10)
  - `CGEventType.keyUp` (bit 11)
  - `CGEventType.flagsChanged` (bit 12)
  - NX_SYSDEFINED (bit 14): for media keys
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
- **Activation Policy:** Accessory (menu bar only). `INFOPLIST_KEY_LSUIElement = YES` plus the runtime `setActivationPolicy(.accessory)` call
- **Info.plist:** Generated (`GENERATE_INFOPLIST_FILE = YES`); configure via `INFOPLIST_KEY_*` settings, not a checked-in file
- **App Sandbox:** Enabled (`ENABLE_APP_SANDBOX = YES`), with `ENABLE_USER_SELECTED_FILES = NO`, because the app opens no file pickers. Entitlements are `com.apple.security.app-sandbox` and `com.apple.security.network.client`, the latter from `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` for the update check. Keep the set this small; add an entitlement only when a feature genuinely needs it.
- **Build number:** `CURRENT_PROJECT_VERSION` must be incremented on every release; it is the `CFBundleVersion` and does not track `MARKETING_VERSION`.
- **Platform settings:** the target is macOS-only. Do not reintroduce `INFOPLIST_KEY_UI*`, `IPHONEOS_DEPLOYMENT_TARGET`, `XROS_DEPLOYMENT_TARGET`, or `SUPPORTS_MACCATALYST`. Xcode adds them to multiplatform templates, but they are inert here.
- **Hardened Runtime:** Enabled
- **Code Signing:** Automatic, Apple Development, team `56JJ9GRL32`

### Building

Local development build:

```bash
xcodebuild -scheme Cleankey -configuration Release -destination 'platform=macOS' build
```

### Releasing

**Always archive. Never ship a plain `build` output.**

```bash
xcodebuild -scheme Cleankey -configuration Release -destination 'platform=macOS' -archivePath ./Cleankey.xcarchive archive
```

Plain `xcodebuild build` injects `com.apple.security.get-task-allow` into the signed app (via the default `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`), regardless of configuration. That entitlement lets any process attach a debugger to the running app, which must never happen for an app that holds a system-wide keyboard event tap. Archiving strips it while keeping the sandbox entitlements.

Do **not** try to fix this by setting `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`; that suppresses the auto-generated entitlements wholesale and silently drops the App Sandbox too.

Verify before distributing:

```bash
codesign -d --entitlements - --xml Cleankey.xcarchive/Products/Applications/Cleankey.app | plutil -convert xml1 -o - -
```

Expected, with the sandbox present and no `get-task-allow`:

```text
com.apple.security.app-sandbox   true
com.apple.security.network.client true
```

#### Automated releases

Pushing a `v*` tag runs `.github/workflows/release.yml`, which performs the same
steps documented below and attaches the zip to the GitHub release. It fails the
build if `get-task-allow` appears in the exported app.

Four repository secrets are required (Settings > Secrets and variables > Actions):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application certificate and private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password chosen during that `.p12` export |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | `56JJ9GRL32` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password from appleid.apple.com |

The workflow builds its own throwaway keychain with a password generated per run,
so no keychain password is stored as a secret, and deletes it afterwards.

#### Signing and notarization

An archive signed with **Apple Development** runs locally but is rejected by
Gatekeeper on any machine that downloads it, because downloaded files carry a
quarantine flag. Distributable builds must be signed with a **Developer ID
Application** certificate and notarized by Apple.

The target deliberately keeps `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`.
Developer ID is applied at export time via `ExportOptions.plist`, so local builds
and Xcode's Run button are unaffected. Do not switch the Signing Certificate in
Xcode's Signing & Capabilities pane. With automatic signing that applies to every
configuration, including Debug.

One-time setup:

1. Xcode → Settings → Accounts → Apple ID → Manage Certificates… → + → **Developer ID Application**.
2. Store notary credentials in the keychain. Never put them in the repo or in a
   command that ends up in shell history:

```bash
xcrun notarytool store-credentials "Cleankey" --apple-id YOUR_APPLE_ID --team-id 56JJ9GRL32
```

   It prompts for an app-specific password, generated at appleid.apple.com under
   Sign-In and Security. Everything afterwards refers to the profile by name only.

Per release:

```bash
xcodebuild -exportArchive -archivePath ./Cleankey.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath ./export
ditto -c -k --keepParent ./export/Cleankey.app ./Cleankey.zip
xcrun notarytool submit ./Cleankey.zip --keychain-profile "Cleankey" --wait
xcrun stapler staple ./export/Cleankey.app
```

Re-zip **after** stapling. The ticket has to be inside the app that is actually
distributed, and the zip submitted for notarization does not contain it.

Verify the result:

```bash
spctl -a -vv ./export/Cleankey.app     # expect: accepted, source=Notarized Developer ID
codesign -dv --verbose=4 ./export/Cleankey.app 2>&1 | grep Authority
```

`ENABLE_HARDENED_RUNTIME = YES` is already set; notarization rejects anything
without it.

---

## Current Issues

- None known.

---

## Version History

The release history was reset on 2026-08-18. Earlier tags (v1.2, v1.2.1, v1.3, and
a short-lived v1.0/v1.0.1/v1.1 renumbering) were deleted, and v1.0 was republished as
the initial full release. Build numbers (`CURRENT_PROJECT_VERSION`) kept climbing
throughout, so they stay monotonic even though the marketing version moved down.

- **v1.0** (current), build 5: initial full release. Keyboard blocking, Open at Login,
  update check, notarized Developer ID build.

---

## Notes for AI Assistants

- Read `README.md` and this file before starting any task; update both before committing (see `AGENTS.md` / `CLAUDE.md`)
- All code is currently in a single file (`Cleankey/CleankeyApp.swift`)
- Project uses modern SwiftUI patterns with Swift Concurrency support (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- Code follows Apple's Swift API design guidelines
- Private types are namespaced within the file
- View modifiers use custom extensions for reusability
