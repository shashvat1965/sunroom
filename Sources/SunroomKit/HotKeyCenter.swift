import Foundation
import AppKit
import Carbon.HIToolbox

/// System-wide hot keys via Carbon's `RegisterEventHotKey`.
///
/// Carbon is deprecated in spirit but remains the only public API that gives a
/// global hot key without Accessibility permission. Every macOS launcher uses it.
@MainActor
public final class HotKeyCenter {
    public struct Combo: Codable, Hashable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// ⌥Space
        public static let optionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        /// ⌃⌥Space
        public static let controlOptionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
        /// ⌥`
        public static let optionGrave = Combo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey))

        public var displayString: String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            parts.append(Self.name(for: keyCode))
            return parts.joined()
        }

        static func name(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_Space: return "Space"
            case kVK_ANSI_Grave: return "`"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_N: return "N"
            default: return "Key \(keyCode)"
            }
        }
    }

    public enum Action: String, CaseIterable, Sendable {
        case toggleCanvas
        case newNote
        case captureDesktop
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static var shared: HotKeyCenter?

    public init() {
        Self.shared = self
        installEventHandler()
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func register(_ combo: Combo, id: UInt32, handler: @escaping () -> Void) {
        unregister(id: id)
        handlers[id] = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x53554E52), id: id) // 'SUNR'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    public func unregister(id: UInt32) {
        handlers.removeValue(forKey: id)
    }

    public func registerAll(_ bindings: [Action: Combo]) {
        for (index, action) in Action.allCases.enumerated() {
            guard let combo = bindings[action] else { continue }
            register(combo, id: UInt32(index + 1)) { [weak self] in
                self?.fire(action)
            }
        }
    }

    /// Set by the app so hot keys can route into the UI layer.
    public var onAction: ((Action) -> Void)?

    func fire(_ action: Action) {
        onAction?(action)
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, let shared = HotKeyCenter.shared else { return OSStatus(eventNotHandledErr) }
                let id = hotKeyID.id
                // Handlers are main-actor bound.
                DispatchQueue.main.async {
                    if let handler = shared.handlers[id] {
                        handler()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}
