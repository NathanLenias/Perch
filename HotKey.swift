import Carbon.HIToolbox

/// A system-wide keyboard shortcut, registered through Carbon's
/// RegisterEventHotKey: works from any app, needs no Accessibility
/// permission (unlike NSEvent keyboard monitors), zero dependencies.
final class HotKey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        // Note: with a single hotkey the handler needs no dispatch; if more
        // hotkeys are ever added, read the EventHotKeyID to tell them apart
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052_4348), id: 1) // 'PRCH'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
