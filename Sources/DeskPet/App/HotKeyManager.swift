import AppKit
import Carbon.HIToolbox
import Foundation

/// 全局快捷键 ⌘⇧H：老板键，随手隐藏金额。
@MainActor
final class HotKeyManager {
    private static let signature = OSType(0x44504B54) // "DPKT"
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
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
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // 回调发生在主线程的事件循环里
            MainActor.assumeIsolated {
                if hotKeyID.signature == HotKeyManager.signature { manager.action() }
            }
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if ProcessInfo.processInfo.environment["DESKPET_DEBUG"] == "1" {
            print("[hotkey] ⌘⇧H 注册状态 \(status == noErr ? "成功" : "失败(\(status))")")
            fflush(stdout)
        }
    }

    // 进程生命周期内不注销：退出时系统会回收全局热键
}
