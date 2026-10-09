import Carbon.HIToolbox
import Foundation

/// A global hotkey via Carbon's `RegisterEventHotKey`, which needs no Accessibility permission.
/// Registration fails with `eventHotKeyExistsErr` (-9878) if another app already owns the combination.
@MainActor
public final class GlobalHotkey {
    public static let defaultKeyCode = UInt32(kVK_Space)
    public static let defaultModifiers = UInt32(cmdKey | optionKey | shiftKey)  // ⌘⌥⇧

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let keyCode: UInt32, modifiers: UInt32, id: UInt32
    private let action: @MainActor () -> Void

    public init(
        keyCode: UInt32 = GlobalHotkey.defaultKeyCode, modifiers: UInt32 = GlobalHotkey.defaultModifiers,
        id: UInt32 = 1, action: @escaping @MainActor () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.id = id
        self.action = action
    }

    /// Registers the hotkey and returns the OS status (0 = success).
    @discardableResult
    public func register() -> OSStatus {
        guard hotKeyRef == nil else { return noErr }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                // Application-target handlers run on the main thread.
                MainActor.assumeIsolated { hotkey.action() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installStatus == noErr else { return installStatus }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5053_4854) /* 'PSHT' */, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr, let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        return status
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
