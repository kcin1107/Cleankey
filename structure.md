# Cleankey Repository Structure

Last updated: 2026-06-08

## Project Overview

**Cleankey** is a macOS menu bar utility that temporarily disables all keyboard input system-wide, useful for cleaning a keyboard without triggering unwanted key presses.

- **Platform:** macOS 13.0+ (Ventura and later)
- **Language:** Swift
- **UI Framework:** SwiftUI
- **Version:** 1.2v1

---

## Repository Layout

```text
Cleankey/
├── .claude/
├── .git/
├── CLAUDE.md
├── README.md
├── STRUCTURE.md
├── Cleankey.xcodeproj/
├── Cleankey/
│   └── Cleankey/
│       ├── Assets.xcassets/
│       ├── CleankeyApp.swift
│       └── CleankeyApp-Info.plist
├── Products/
│   └── Cleankey.app
└── Releases/
```

### Key Files

- `CLAUDE.md` — Project instructions for AI coding assistants.
- `README.md` — Project overview and user-facing documentation.
- `STRUCTURE.md` — This file: repository structure and app architecture reference.
- `Cleankey.xcodeproj/` — Xcode project bundle.
- `Cleankey/Cleankey/CleankeyApp.swift` — Main SwiftUI app source (all code currently in this single file).
- `Cleankey/Cleankey/CleankeyApp-Info.plist` — App Info.plist.
- `Cleankey/Cleankey/Assets.xcassets/` — App asset catalog.
- `Releases/` — Release artifacts.

---

## Code Architecture

All code currently lives in `CleankeyApp.swift`.

### 1. `CleankeyApp` (SwiftUI App)
- **Type:** `@main struct` conforming to `App`
- **Purpose:** Main application entry point
- **Key Features:**
  - Uses `MenuBarExtra` for menu bar presence (macOS 13+)
  - Dynamic icon: `keyboard` (inactive) / `keyboard.fill` (active)
  - Menu bar UI with toggle switch, settings shortcuts, version, and quit button
  - 256pt fixed width menu
  - Window-style menu bar extra (`.menuBarExtraStyle(.window)`)

### 2. `KeyboardBlocker` (ObservableObject)
- **Type:** `final class` conforming to `ObservableObject`
- **Purpose:** Core functionality — system-wide keyboard input blocking
- **Key Properties:**
  - `@Published var isBlocking: Bool` — Current blocking state
  - `private var eventTap: CFMachPort?` — Low-level event tap
  - `private var runLoopSource: CFRunLoopSource?` — Run loop integration

**Key Methods:**
- `startBlocking()` — Creates CGEvent tap at HID level, intercepts all keyboard events
- `stopBlocking()` — Removes event tap and restores normal input
- `requestAccessibilityPermissionIfNeeded()` — Prompts for Accessibility permissions
- `eventTapCallback` — Static callback that filters events (blocks keys when active)

**Event Handling:**
- Blocks: Key down, key up, modifier flags, media keys (volume, brightness, play/pause)
- Uses `.cghidEventTap` for system-wide interception
- Returns `nil` to drop events, `Unmanaged.passUnretained(event)` to allow through
- Handles tap timeout/disable by re-enabling automatically

### 3. `AppDelegate` (NSApplicationDelegate)
- **Type:** `final class` conforming to `NSObject, NSApplicationDelegate`
- **Purpose:** App lifecycle management
- **Key Feature:** Sets activation policy to `.accessory` (no Dock icon, menu bar only)

### 4. `SystemSettingsOpener` (Utility Struct)
- **Type:** `private struct` with static methods
- **Purpose:** Opens specific System Settings privacy panes
- **Supported Panes:**
  - `.inputMonitoring` — Input Monitoring settings
  - `.accessibility` — Accessibility settings
- **Implementation:** Uses URL schemes with fallbacks for older macOS versions

### 5. `HoverRow` (ViewModifier)
- **Type:** `private struct` conforming to `ViewModifier`
- **Purpose:** Adds hover effect to menu items
- **Style:** Rounded rectangle with 15% opacity secondary color on hover

---

## Dependencies

### System Frameworks
- `SwiftUI` — UI framework
- `Cocoa` — macOS AppKit integration
- `ApplicationServices` — CGEvent and accessibility APIs
- `Combine` — Reactive programming (imported but not actively used)

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
    ├── Divider
    ├── VStack — Settings Buttons (4pt spacing)
    │   ├── Button("Input Monitoring Settings…") [with hover effect]
    │   └── Button("Accessibility Settings…") [with hover effect]
    ├── Divider
    └── HStack — Footer
        ├── Text("v1.2v1")
        └── Button("Quit")
```

---

## Features

### Implemented
- System-wide keyboard blocking (all keys + media keys)
- Menu bar toggle control
- Automatic permission requests
- Direct links to System Settings privacy panes
- Hover effects on menu items
- Auto-recovery from event tap timeouts
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
- Uses `Unmanaged` for passing Swift objects to C callbacks
- Properly cleans up event tap in `deinit`
- Uses weak self references in async closures

---

## Build Configuration

- **Minimum Deployment Target:** macOS 13.0 (for `MenuBarExtra`)
- **Architecture:** Universal (Apple Silicon + Intel)
- **App Category:** Utilities
- **Activation Policy:** Accessory (menu bar only)

---

## Current Issues

- None known after updating the target destinations to macOS.

---

## Version History

- **v1.2v1** (current) — As documented in menu bar UI

---

## Notes for AI Assistants

- All code is currently in a single file (`CleankeyApp.swift`)
- Project uses modern SwiftUI patterns with Swift Concurrency support
- Code follows Apple's Swift API design guidelines
- Private types are namespaced within the file
- View modifiers use custom extensions for reusability
