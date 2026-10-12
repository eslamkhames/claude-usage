import AppKit
import Carbon.HIToolbox

extension HotKeyChoice {
    var keyCode: UInt32 {
        switch self {
        case .ctrlOptC: UInt32(kVK_ANSI_C)
        case .ctrlOptU, .cmdOptU: UInt32(kVK_ANSI_U)
        case .cmdShiftK: UInt32(kVK_ANSI_K)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .ctrlOptC, .ctrlOptU: UInt32(controlKey | optionKey)
        case .cmdOptU: UInt32(cmdKey | optionKey)
        case .cmdShiftK: UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func apply() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard Prefs.hotKeyEnabled else { return }

        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in StatusItemPanel.toggle() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let choice = Prefs.hotKey
        let id = EventHotKeyID(signature: OSType(0x434C_4252), id: 1) // "CLBR"
        let status = RegisterEventHotKey(choice.keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("ClaudeBar: shortcut \(choice.title) is taken (\(status))") }
    }
}

/// SwiftUI has no API to open a MenuBarExtra's window, so click its status item button.
enum StatusItemPanel {
    @MainActor static func toggle() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    @MainActor private static func findButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}
