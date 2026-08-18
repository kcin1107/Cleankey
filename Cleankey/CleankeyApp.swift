import SwiftUI
import Cocoa
import ApplicationServices
// Combine provides ObservableObject and @Published; member import visibility is
// enabled, so SwiftUI does not re-export them implicitly.
import Combine

/// Marketing version from the generated Info.plist, so the menu never drifts from the build.
private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

/// NX_SYSDEFINED / NSEvent.EventType.systemDefined. Carries the media keys
/// (play/pause, brightness, volume), which `CGEventType` has no case for.
private let nxSysDefinedEventType: UInt32 = 14

/// NX_SUBTYPE_AUX_CONTROL_BUTTONS — marks a system-defined event as a media key.
private let nxAuxControlButtonsSubtype: Int16 = 8

private enum PrivacyPane { case inputMonitoring, accessibility }

private enum SystemSettingsOpener {
    static func open(_ pane: PrivacyPane) {
        // NSWorkspace.open() reports success for any x-apple.systempreferences URL,
        // even when the anchor is unknown — an unknown anchor just lands on the
        // generic Privacy & Security page. So there is no way to detect a bad anchor
        // and fall back; it has to be correct the first time.
        // Input Monitoring's anchor is Privacy_ListenEvent. There is no
        // Privacy_InputMonitoring anchor.
        let anchor: String
        switch pane {
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shared look for the settings rows: full width, padded, highlighted on hover.
private struct SettingsRow: ViewModifier {
    @State private var isHover = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .onHover { isHover = $0 }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHover ? Color.secondary.opacity(0.15) : Color.clear)
            )
    }
}

private extension View {
    func settingsRow() -> some View { modifier(SettingsRow()) }
}

@main
struct CleankeyApp: App {
    @StateObject private var blocker = KeyboardBlocker()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cleankey", systemImage: blocker.isBlocking ? "keyboard.fill" : "keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Keyboard Cleaning")
                        .font(.body)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { blocker.isBlocking },
                        set: { blocker.setBlocking($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)

                if let failureMessage = blocker.failureMessage {
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }

                Divider()

                VStack(spacing: 4) {
                    Button("Input Monitoring Settings…") {
                        SystemSettingsOpener.open(.inputMonitoring)
                    }
                    .settingsRow()

                    Button("Accessibility Settings…") {
                        SystemSettingsOpener.open(.accessibility)
                    }
                    .settingsRow()
                }

                Divider()

                HStack {
                    Text("v\(appVersion)")
                        .font(.body)

                    Spacer()

                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.body)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .padding(8)
            .frame(width: 256)
            .onAppear {
                blocker.requestAccessibilityPermissionIfNeeded()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we live only in the menu bar (no Dock icon/app switcher)
        NSApp.setActivationPolicy(.accessory)
    }
}

final class KeyboardBlocker: ObservableObject {
    /// Owned here rather than written by the view: it turns true only once the tap is
    /// installed, so the switch can never show a lock that isn't actually in effect.
    @Published private(set) var isBlocking: Bool = false

    /// Set when the event tap could not be created, so the menu can explain why the
    /// switch stayed off instead of leaving the user guessing.
    @Published private(set) var failureMessage: String?

    // Event tap state
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Public control

    /// Single entry point for the menu's switch.
    func setBlocking(_ shouldBlock: Bool) {
        if shouldBlock {
            startBlocking()
        } else {
            stopBlocking()
        }
    }

    func startBlocking() {
        guard eventTap == nil else { return }
        // Ensure we have accessibility trust; the system may disable the tap otherwise.
        requestAccessibilityPermissionIfNeeded()

        // Key down, key up, modifier changes, and the system-defined events that
        // carry media keys (play/pause, brightness, volume).
        let eventTypes: [UInt64] = [
            UInt64(CGEventType.keyDown.rawValue),
            UInt64(CGEventType.keyUp.rawValue),
            UInt64(CGEventType.flagsChanged.rawValue),
            UInt64(nxSysDefinedEventType)
        ]
        let mask = eventTypes.reduce(into: UInt64(0)) { $0 |= 1 << $1 }

        // Create the event tap at the HID level so we can suppress events system-wide.
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: KeyboardBlocker.eventTapCallback,
            userInfo: refcon
        ) else {
            // The tap almost always fails because Accessibility or Input Monitoring
            // access hasn't been granted. Stay unblocked and say why.
            failureMessage = "Couldn't lock the keyboard. Grant Cleankey access below, then try again."
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)

        failureMessage = nil
        isBlocking = true
    }

    func stopBlocking() {
        teardownTap()
        isBlocking = false
    }

    /// Tears the tap down without touching published state, so `deinit` can reuse it.
    private func teardownTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Invalidate the Mach port so it isn't leaked on every toggle cycle.
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
    }

    // MARK: - Accessibility Permissions

    func requestAccessibilityPermissionIfNeeded() {
        // Ask the system to prompt the user to grant Accessibility permissions if not already granted.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Tap Callback

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        let passThrough = Unmanaged.passUnretained(event)

        // Without the refcon there is no way to know whether we should be blocking,
        // so let the event through.
        guard let refcon = refcon else { return passThrough }
        let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()

        // If the tap gets disabled by the system (e.g., timeout), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = blocker.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return passThrough
        }

        guard blocker.isBlocking else { return passThrough }

        // System-defined events cover more than media keys, so drop only the aux
        // control button subtype and let the rest through.
        if type.rawValue == nxSysDefinedEventType {
            let isMediaKey = NSEvent(cgEvent: event)?.subtype.rawValue == nxAuxControlButtonsSubtype
            return isMediaKey ? nil : passThrough
        }

        return nil
    }

    deinit {
        teardownTap()
    }
}
