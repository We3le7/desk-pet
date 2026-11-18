import AppKit
import SwiftUI

/// 设置窗口（独立于宠物悬浮窗，可聚焦）。
@MainActor
final class SettingsWindowController {
    private let controller: EarningsController
    private let appearance: AppearanceStore
    private let catalog: PetsCatalog
    private let ui: SettingsUIState
    private var window: NSWindow?

    init(controller: EarningsController, appearance: AppearanceStore, catalog: PetsCatalog, ui: SettingsUIState) {
        self.controller = controller
        self.appearance = appearance
        self.catalog = catalog
        self.ui = ui
    }

    /// 打开设置并切到指定标签页
    func show(tab: SettingsTab? = nil) {
        if let tab { ui.tab = tab }
        show()

        // 金额页打开后直接聚焦金额输入框，省一次点击
        if ui.tab == .earnings, let window {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window,
                      let field = self?.firstEditableTextField(in: window.contentView) else { return }
                window.makeFirstResponder(field)
            }
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 诊断：窗口是否拿到键盘焦点、输入框能否进入编辑态。
    func diagnoseKeyboardFocus() {
        guard let window else {
            print("[focus] 没有窗口")
            return
        }
        print("[focus] NSApp.isActive=\(NSApp.isActive) isKeyWindow=\(window.isKeyWindow) styleMask=\(window.styleMask.rawValue) level=\(window.level.rawValue)")
        print("[focus] activationPolicy=\(NSApp.activationPolicy().rawValue)")

        guard let field = firstEditableTextField(in: window.contentView) else {
            print("[focus] 没找到可编辑输入框")
            return
        }
        print("[focus] textField editable=\(field.isEditable) selectable=\(field.isSelectable) enabled=\(field.isEnabled) string=\(field.stringValue)")

        window.makeFirstResponder(field)
        let editor = field.currentEditor()
        print("[focus] makeFirstResponder → currentEditor=\(editor != nil)")

        if let editor {
            editor.insertText("12345")
            print("[focus] 模拟键入后 field=\(field.stringValue) editor=\(editor.string)")
        }

        // 命中测试：鼠标点在输入框中心，真的能落到输入框上吗？
        if let content = window.contentView {
            let centerInField = NSPoint(x: field.bounds.midX, y: field.bounds.midY)
            let inWindow = field.convert(centerInField, to: nil)
            let hit = content.hitTest(inWindow)
            print("[focus] field.frame=\(field.frame) 中心(窗口坐标)=\(inWindow)")
            print("[focus] hitTest → \(String(describing: hit.map { type(of: $0) })) 是否为输入框=\(hit === field)")
            var chain: [String] = []
            var node: NSView? = field
            while let current = node {
                chain.append("\(type(of: current))")
                node = current.superview
            }
            print("[focus] 视图链: \(chain.joined(separator: " < "))")
        }

        // 滑轮选择是否生效：选中一项并派发 action，看配置是否更新
        if let content = window.contentView {
            let combos = collectComboBoxes(in: content)
            print("[focus] 找到 \(combos.count) 个滑轮，选中值=\(combos.map(\.stringValue))")
            if let workdaysCombo = combos.first, workdaysCombo.numberOfItems > 2 {
                // 1) 滚轮/下拉选择
                workdaysCombo.selectItem(at: 2)
                workdaysCombo.sendAction(workdaysCombo.action, to: workdaysCombo.target)
                print("[focus] 下拉选中 \(workdaysCombo.stringValue) → workdaysPerMonth=\(controller.config.workdaysPerMonth)")

                // 2) 直接键入数字，看是否被接受并吸附到刻度
                workdaysCombo.stringValue = "22.07"
                NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: workdaysCombo)
                print("[focus] 键入 22.07 后 → workdaysPerMonth=\(controller.config.workdaysPerMonth) 显示=\(workdaysCombo.stringValue)")
            }
        }

        // 时序测试：进入编辑后等 2.5 秒（期间会经过多次 1Hz 刷新），看内容是否被冲掉
        let identity = ObjectIdentifier(field)
        print("[focus] 已排定 2.5 秒后的检查")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let window = self?.window else { return }
            let again = self?.firstEditableTextField(in: window.contentView)
            let editing = again?.currentEditor() != nil
            let text = again?.currentEditor()?.string ?? again?.stringValue ?? "<nil>"
            print("[focus] 2.5 秒后 同一实例=\((again.map(ObjectIdentifier.init) == identity)) 编辑中=\(editing) 内容=\(text)")
            fflush(stdout)
            exit(0)
        }
        fflush(stdout)
    }

    private func collectComboBoxes(in view: NSView) -> [NSComboBox] {
        var found: [NSComboBox] = []
        if let combo = view as? NSComboBox { found.append(combo) }
        for subview in view.subviews {
            found.append(contentsOf: collectComboBoxes(in: subview))
        }
        return found
    }

    private func firstEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = firstEditableTextField(in: subview) { return found }
        }
        return nil
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(
            controller: controller,
            appearance: appearance,
            catalog: catalog,
            ui: ui
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)

        let window = NSWindow(
            contentRect: hosting.bounds,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskPet 设置"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
