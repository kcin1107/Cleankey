import SwiftUI
import Cocoa
import ApplicationServices
import Combine

/// Marketing version from the generated Info.plist, so the menu never drifts from the build.
private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

private enum PrivacyPane { case inputMonitoring, accessibility }

private struct SystemSettingsOpener {
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

private struct HoverRow: ViewModifier {
    @State private var isHover = false
    func body(content: Content) -> some View {
        content
            .onHover { isHover = $0 }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHover ? Color.secondary.opacity(0.15) : Color.clear)
            )
    }
}

private extension View {
    func hoverRow() -> some View { self.modifier(HoverRow()) }
}

@main
struct CleankeyApp: App {
    @StateObject private var blocker = KeyboardBlocker()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // MenuBarExtra is available on macOS 13+
        MenuBarExtra("Cleankey", systemImage: blocker.isBlocking ? "keyboard.fill" : "keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Keyboard Cleaning")
                        .font(.body)

                    Spacer()

                    Toggle("", isOn: $blocker.isBlocking)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .fixedSize()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)

                Divider()

                VStack(spacing: 4) {
                    Button("Input Monitoring Settings…") {
                        SystemSettingsOpener.open(.inputMonitoring)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .hoverRow()

                    Button("Accessibility Settings…") {
                        SystemSettingsOpener.open(.accessibility)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .hoverRow()
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
            .onChange(of: blocker.isBlocking) { _, newValue in
                if newValue {
                    blocker.startBlocking()
                } else {
                    blocker.stopBlocking()
                }
            }
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
    @Published var isBlocking: Bool = false

    // Event tap state
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Public control

    func startBlocking() {
        guard eventTap == nil else { return }
        // Ensure we have accessibility trust; the system may disable the tap otherwise.
        requestAccessibilityPermissionIfNeeded()

        // Build an event mask for key down, key up, modifier changes,
        // and NX_SYSDEFINED (system-defined) events which carry media keys
        // (play/pause, brightness, volume, etc.).
        let nxSysDefined: UInt64 = 14 // NX_SYSDEFINED / NSEvent.EventType.systemDefined
        let mask = (
            (1 as UInt64) << CGEventType.keyDown.rawValue
        ) | (
            (1 as UInt64) << CGEventType.keyUp.rawValue
        ) | (
            (1 as UInt64) << CGEventType.flagsChanged.rawValue
        ) | (
            (1 as UInt64) << nxSysDefined
        )

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
            // If the tap can't be created (often due to permissions), leave blocking off.
            DispatchQueue.main.async { [weak self] in self?.isBlocking = false }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopBlocking() {
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

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        // If the tap gets disabled by the system (e.g., timeout), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let refcon = refcon {
                let me = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                if let tap = me.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Swallow all key events while blocking is active.
        // If, for any reason, we're not supposed to be blocking, let the event pass through.
        if let refcon = refcon {
            let me = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
            if me.isBlocking {
                // For NX_SYSDEFINED events, only block media/special key events
                // (subtype 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS), let others pass.
                let nxSysDefined: UInt32 = 14
                if type.rawValue == nxSysDefined {
                    let nsEvent = NSEvent(cgEvent: event)
                    if nsEvent?.subtype.rawValue == 8 {
                        return nil // Drop media key event
                    }
                    return Unmanaged.passUnretained(event)
                }
                return nil // Drop the event
            } else {
                return Unmanaged.passUnretained(event)
            }
        }

        // Fallback: allow the event if we can't determine state.
        return Unmanaged.passUnretained(event)
    }

    deinit {
        stopBlocking()
    }
}
