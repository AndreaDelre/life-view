import AppKit
import Carbon.HIToolbox
import Core

/// A thin wrapper around Carbon's `RegisterEventHotKey` API.
///
/// Carbon's hotkey APIs remain the supported way to register a system-wide hotkey
/// on macOS that does **not** require Accessibility entitlements (which a Mac App
/// Store / sandboxed build cannot grant itself). Each ``GlobalHotKey`` instance
/// owns one registration and invokes ``handler`` on the main actor when fired.
///
/// **Sandbox note**: Carbon hotkeys are allowed under the standard App Sandbox.
/// They do **not** require `com.apple.security.temporary-exception` entries.
/// If registration fails at runtime, the app logs the `OSStatus` and continues —
/// the menu bar icon still works as a fallback.
/// Four-char code `'LVHK'` — LifeView HotKey. Top-level constant so it can be
/// read from both main-actor and Carbon-callback contexts without isolation
/// dance.
let lifeViewHotKeySignature: OSType = {
    let chars: [UInt8] = [0x4C, 0x56, 0x48, 0x4B] // 'L','V','H','K'
    return chars.reduce(0) { ($0 << 8) | OSType($1) }
}()

@MainActor
final class GlobalHotKey {
    private let registration: HotKeyRegistry.Registration

    init?(combo: HotKeyCombo, handler: @escaping @MainActor () -> Void) {
        guard let registered = HotKeyRegistry.shared.register(combo: combo, handler: handler) else {
            return nil
        }
        self.registration = registered
    }

    deinit {
        // `Registration` is `Sendable`, deinit is non-isolated by default in Swift 6.
        HotKeyRegistry.shared.unregister(registration)
    }
}

// MARK: - Registry

/// Thread-safe registry that bridges Carbon C callbacks back into Swift land.
///
/// The Carbon event handler runs on whichever thread the OS dispatches it on
/// (typically the main run loop, but we do not rely on that). Calls are
/// serialised by an internal lock; user handlers are hopped to the main actor
/// before being invoked.
final class HotKeyRegistry: @unchecked Sendable {
    static let shared = HotKeyRegistry()

    private let lock = NSLock()
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private var eventHandlerRef: EventHandlerRef?

    /// Opaque token returned by ``register(combo:handler:)``.
    ///
    /// `EventHotKeyRef` is an `OpaquePointer` so it is not auto-`Sendable`; we
    /// hand-wave that with `@unchecked` because the pointer is read-only after
    /// registration and ultimately freed by `UnregisterEventHotKey`.
    struct Registration: @unchecked Sendable {
        let identifier: UInt32
        let hotKeyRef: EventHotKeyRef
    }

    private init() {}

    func register(
        combo: HotKeyCombo,
        handler: @escaping @MainActor () -> Void
    ) -> Registration? {
        lock.lock()
        let identifier = nextID
        nextID += 1
        handlers[identifier] = handler
        let installed = ensureHandlerInstalledLocked()
        lock.unlock()

        guard installed else {
            lock.lock()
            handlers.removeValue(forKey: identifier)
            lock.unlock()
            return nil
        }

        var ref: EventHotKeyRef?
        let modifiers = Self.carbonModifiers(from: combo.modifiers)
        let hotKeyID = EventHotKeyID(signature: lifeViewHotKeySignature, id: identifier)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let validRef = ref else {
            NSLog("[GlobalHotKey] RegisterEventHotKey failed: OSStatus=\(status)")
            lock.lock()
            handlers.removeValue(forKey: identifier)
            lock.unlock()
            return nil
        }
        return Registration(identifier: identifier, hotKeyRef: validRef)
    }

    func unregister(_ registration: Registration) {
        UnregisterEventHotKey(registration.hotKeyRef)
        lock.lock()
        handlers.removeValue(forKey: registration.identifier)
        lock.unlock()
    }

    fileprivate func dispatch(identifier: UInt32) {
        lock.lock()
        let handler = handlers[identifier]
        lock.unlock()
        guard let handler else { return }
        // Hop to main actor — Carbon does not guarantee a specific thread.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                handler()
            }
        }
    }

    private func ensureHandlerInstalledLocked() -> Bool {
        if handlerInstalled { return true }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if err != noErr { return err }
                HotKeyRegistry.shared.dispatch(identifier: hkID.id)
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
        if status != noErr {
            NSLog("[GlobalHotKey] InstallEventHandler failed: OSStatus=\(status)")
            return false
        }
        eventHandlerRef = handlerRef
        handlerInstalled = true
        return true
    }

    /// Maps Cocoa modifier flags to Carbon hotkey modifier flags.
    static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if cocoa.contains(.command) { out |= UInt32(cmdKey) }
        if cocoa.contains(.option) { out |= UInt32(optionKey) }
        if cocoa.contains(.control) { out |= UInt32(controlKey) }
        if cocoa.contains(.shift) { out |= UInt32(shiftKey) }
        return out
    }
}
