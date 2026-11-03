import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "com.rkrev.checkpoint", category: "GlobalHotKey")

/// A system-wide keyboard shortcut (#15). Uses Carbon's RegisterEventHotKey, which needs
/// no Accessibility permission and only sees this one key combination.
@MainActor
final class GlobalHotKey {

    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: a `kVK_…` virtual key code
    ///   - modifiers: Carbon modifier flags (`cmdKey | optionKey | controlKey | shiftKey`)
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Application-target Carbon events arrive on the main thread
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, context, &handlerRef)
        guard installed == noErr else {
            log.error("InstallEventHandler failed: \(installed)")
            return nil
        }

        let id = EventHotKeyID(signature: OSType(0x4348_4B50), id: 1)  // 'CHKP'
        let registered = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            // Another app may already own this combination
            log.error("RegisterEventHotKey failed: \(registered)")
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
