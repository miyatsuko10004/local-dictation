import DictationCore
import AppKit
import ApplicationServices
import Carbon

struct FocusSnapshot {
    let pid: pid_t
    let element: AXUIElement
    static func capture() -> FocusSnapshot? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        var role: CFTypeRef?, subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        let allowed = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        guard let role = role as? String, allowed.contains(role),
              subrole as? String != kAXSecureTextFieldSubrole else { return nil }
        return FocusSnapshot(pid: app.processIdentifier, element: element)
    }
    func isCurrent() -> Bool {
        guard let now = Self.capture() else { return false }
        return now.pid == pid && CFEqual(now.element, element)
    }
}

@MainActor enum TextInsertion {
    static func paste(_ text: String, into target: FocusSnapshot?) async -> Bool {
        guard !Task.isCancelled, CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty,
              let target, target.isCurrent(), AXIsProcessTrusted(), !text.isEmpty,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        board.clearContents()
        guard board.setString(text, forType: .string) else { return false }
        let ownChange = board.changeCount
        // Recheck after writing the clipboard, before sending keys.
        let stillCurrent = target.isCurrent()
        if stillCurrent {
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if board.changeCount == ownChange {
            board.clearContents()
            let items = saved.map { types -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
        // Key dispatch is not proof the receiving application accepted the text.
        return stillCurrent
    }
}

@MainActor final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var rightShiftDown = false
    private func handleShift(_ event: NSEvent) {
        guard event.keyCode == 60 else { return }
        // Device-specific bit distinguishes right Shift even when left Shift is held.
        let down = RightShiftShortcut.isPressed(keyCode: UInt32(event.keyCode), flags: UInt64(event.modifierFlags.rawValue))
        guard down != rightShiftDown else { return }
        rightShiftDown = down
        action?(down)
    }
    var action: ((Bool) -> Void)?
    func register(code: UInt32 = 49, modifiers: UInt32 = UInt32(cmdKey | optionKey)) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        rightShiftDown = false
        if code == 60 && modifiers == 0 {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleShift(event)
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleShift(event)
                return event
            }
            return globalMonitor != nil && localMonitor != nil
        }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let key = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Task { @MainActor in key.action?(pressed) }
            return noErr
        }, 2, &types, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x4C444943, id: 1)
        return RegisterEventHotKey(code, modifiers, id,
                                  GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    static func display(code: UInt32, modifiers: UInt32) -> String {
        if code == 60 && modifiers == 0 { return "右Shift" }
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        let keys: [UInt32:String] = [49:"Space",0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",120:"F2"]
        return result + (keys[code] ?? "Key \(code)")
    }
    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
