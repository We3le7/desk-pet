import AppKit
import DeskPetCore
import SwiftUI

/// 首次点击就能操作（不等"先激活窗口"那一下）。后台 app 的窗口第一下点击默认只用来激活，
/// 表现为"点了没反应、打字没反应"。
final class FirstMouseTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FirstMouseComboBox: NSComboBox {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 通用可滚动选择器：用 `NSComboBox` 实现 macOS 上缺失的「滑轮」式选择。
///
/// 之所以不用 SwiftUI 的 `Picker`：`.wheel` 样式在 macOS 不可用，而 `.menu` 是弹出菜单，
/// 都不是滚轮滚动的手感。
struct ScrollingValuePicker: NSViewRepresentable {
    let values: [Double]
    let label: (Double) -> String
    @Binding var selection: Double
    var width: CGFloat = 88

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var values: [Double] = []
        var label: (Double) -> String = { "\($0)" }
        var selection: Binding<Double>

        init(selection: Binding<Double>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSComboBox) {
            let index = sender.indexOfSelectedItem
            guard index >= 0, index < values.count else { return }
            selection.wrappedValue = values[index]
        }

        /// 允许直接键入数字：提交时吸附到最近的刻度，避免出现列表里没有的值。
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            let text = combo.stringValue.trimmingCharacters(in: .whitespaces)
            guard let typed = Double(text), !values.isEmpty else {
                combo.stringValue = label(selection.wrappedValue)
                return
            }
            let snapped = values.min { abs($0 - typed) < abs($1 - typed) } ?? typed
            selection.wrappedValue = snapped
            combo.stringValue = label(snapped)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSComboBox {
        let combo = FirstMouseComboBox()
        // 既能滚轮选，也能直接打字（提交时吸附到最近刻度）
        combo.isEditable = true
        combo.completes = false
        combo.numberOfVisibleItems = 12
        combo.usesDataSource = false
        combo.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        combo.addItems(withObjectValues: values.map(label))
        context.coordinator.values = values
        context.coordinator.label = label
        combo.delegate = context.coordinator
        combo.target = context.coordinator
        combo.action = #selector(Coordinator.changed(_:))
        combo.selectItem(at: nearestIndex)
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.values = values
        context.coordinator.label = label
        context.coordinator.selection = $selection
        // 正在输入时不要抢内容
        if combo.currentEditor() != nil { return }
        let target = nearestIndex
        if target >= 0, combo.indexOfSelectedItem != target {
            combo.selectItem(at: target)
        }
    }

    /// 当前值在列表里最接近的下标（历史值不在刻度上时也能正确显示）
    private var nearestIndex: Int {
        guard !values.isEmpty else { return -1 }
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, value) in values.enumerated() {
            let distance = abs(value - selection)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

/// 金额输入框：用 `NSTextField` 而不是 SwiftUI `TextField`。
///
/// 设置页因为金额 5Hz 刷新会不停重建，SwiftUI 输入框会被冲掉光标与字符；
/// AppKit 控件在重建时保持不变，回车或失焦时再提交。
struct MoneyTextField: NSViewRepresentable {
    @Binding var value: Double
    var width: CGFloat = 110

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var binding: Binding<Double>
        var isEditing = false

        init(binding: Binding<Double>) {
            self.binding = binding
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            // 点进输入框即全选，输入新数字直接覆盖
            if let field = notification.object as? NSTextField, let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: editor.string.count)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            commit(notification.object as? NSTextField)
        }

        @objc func submit(_ sender: NSTextField) {
            commit(sender)
        }

        func commit(_ field: NSTextField?) {
            guard let field else { return }
            if let parsed = MoneyFormat.parse(field.stringValue) {
                binding.wrappedValue = parsed
            }
            // 规范化回显（例如输入 21000）→ "21,000"
            field.stringValue = Self.display(binding.wrappedValue)
        }

        static func display(_ value: Double) -> String {
            let integer = Int(value.rounded())
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: integer)) ?? "\(integer)"
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $value) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FirstMouseTextField()
        field.alignment = .right
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.stringValue = Coordinator.display(value)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.binding = $value
        // 只要还在编辑（有 field editor 或 delegate 说在编辑），就绝不覆盖内容。
        // 之前只靠 controlTextDidBeginEditing 的标记，漏判时 1Hz 刷新会把刚敲的字冲掉。
        let isEditing = context.coordinator.isEditing || field.currentEditor() != nil
        guard !isEditing else { return }
        let display = Coordinator.display(value)
        if field.stringValue != display {
            field.stringValue = display
        }
    }
}
