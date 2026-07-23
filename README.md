<img src="Cleankey/Assets.xcassets/AppIcon.appiconset/iconMacOS (128px 1x) 1.png" width="96" alt="Cleankey app icon — a macOS menu bar keyboard lock utility">

# Cleankey — Lock Your Keyboard to Clean It (macOS Menu Bar App)

**Cleankey is a tiny, free macOS menu bar app that temporarily locks your keyboard so you can wipe down the keys without triggering accidental keystrokes.** Flip the toggle on, clean at your leisure, flip it off. That's it.

![Cleankey demo — toggling keyboard lock on and off from the macOS menu bar to clean a keyboard safely](CleankeyDemo.gif)

---

## Why Cleankey?

Wiping down a Mac keyboard normally fires off a storm of keystrokes — opening apps, deleting text, changing volume, even triggering shortcuts. Cleankey blocks **all** keyboard input system-wide with a single toggle, so you can clean safely. No accidental typing, no surprise actions.

- **Lock your keyboard instantly** — one click in the menu bar
- **Blocks every key** — letters, numbers, modifiers (⌘ ⌥ ⌃ ⇧), and media keys (volume, brightness, play/pause)
- **Lives in the menu bar** — no Dock icon, no app switcher clutter
- **Instant off** — everything returns to normal the moment you toggle back
- **Lightweight & native** — built in Swift/SwiftUI, no background bloat

## How it works

Cleankey installs a system-wide event tap at the HID level, intercepting key events before they reach any app. While blocking is active, all keyboard input — including modifier keys and media keys like play/pause and volume — is silently dropped. Toggle it off and everything returns to normal instantly.

Because it operates at the HID level, Cleankey needs two permissions:

- **Accessibility** — to create the event tap
- **Input Monitoring** — to intercept keyboard events system-wide

Both can be granted in System Settings. Cleankey includes shortcuts to jump straight there.

## Requirements

- macOS 14.0 (Sonoma) or later
- Works on Apple Silicon and Intel Macs

## Installation

Two options:
1. Download the .zip archive on the "Releases" section on here and simply drop the `Cleankey.app` file into your `/Applications` (or wherever you want).
2. Download the whole repository, build the project in Xcode and drop `Cleankey.app` into your `/Applications` folder.

Cleankey lives entirely in the menu bar, which means no Dock icon, no app switcher entry. As simple as it gets.

## FAQ

**How do I unlock the keyboard once it's locked?**
Click the Cleankey icon in the menu bar with your mouse or trackpad and flip the toggle off. The mouse stays fully functional while the keyboard is locked.

**Does Cleankey block media and function keys too?**
Yes. Volume, brightness, and play/pause/media keys are all blocked while cleaning mode is on, so wiping the top row won't change your settings.

**Why does Cleankey need Accessibility and Input Monitoring permissions?**
Both are required by macOS to intercept keyboard events system-wide. Cleankey only uses them to drop keystrokes while locking is active — it does not log, store, or transmit anything you type.

**Is Cleankey safe? Does it record my keystrokes?**
No. Cleankey simply drops key events while active and never reads, saves, or sends them anywhere.

**Will it disable my keyboard permanently if the app crashes?**
No. The keyboard lock only exists while Cleankey is running and toggled on. Quitting the app restores normal input immediately.

---

Made by [Nick Ringelmann](https://nickringelmann.com)
