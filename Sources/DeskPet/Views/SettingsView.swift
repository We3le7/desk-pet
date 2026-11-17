import AppKit
import SwiftUI
import DeskPetCore

/// 设置面板：薪资、工时、暂停与金额显示。
struct SettingsView: View {
    @ObservedObject var controller: EarningsController
    @ObservedObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上班鼓励器")
                .font(.system(size: 15, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("税后月薪", unit: "元") { numberField(doubleBinding(\.monthlyNet), width: 88) }
                row("月均工作日", unit: "天") { numberField(doubleBinding(\.workdaysPerMonth), width: 88) }
                row("每日工时", unit: "小时") { numberField(doubleBinding(\.hoursPerDay), width: 88) }
                row("年终额外月数", unit: "月") { numberField(doubleBinding(\.extraMonthsPerYear), width: 88) }
                row("上班时间", unit: "") {
                    timeWheels(\SalaryConfig.startMinuteOfDay)
                }
                row("下班时间", unit: "") {
                    timeWheels(\SalaryConfig.endMinuteOfDay)
                }
                row("午休扣除", unit: "分钟") { numberField(intBinding(\.lunchBreakMinutes), width: 88) }
            }

            Divider()

            Text("宠物")
                .font(.system(size: 13, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("大小", unit: String(format: "%.0f%%", appearance.petScale * 100)) {
                    Slider(
                        value: Binding(
                            get: { appearance.petScale },
                            set: { appearance.petScale = $0 }
                        ),
                        in: 0.6...2.0,
                        step: 0.05
                    )
                    .frame(width: 170)
                }
                GridRow {
                    Text("空闲轮播").font(.system(size: 12)).foregroundColor(.secondary)
                        .frame(width: 88, alignment: .leading)
                    Toggle("空闲时轮播不同动作", isOn: Binding(
                        get: { appearance.rotateActions },
                        set: { appearance.rotateActions = $0 }
                    ))
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.config.summary)
                    .font(.system(size: 12).monospacedDigit())
                Text("今日已到账 \(MoneyFormat.yuan(controller.amount.total))"
                     + (controller.isPaused ? "（已暂停）" : ""))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
                Text("按在岗时长计钱：合同时薪 × 在岗秒数，不是把月薪均摊到窗口。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button(controller.isPaused ? "继续" : "暂停") {
                    controller.togglePause()
                }
                Toggle("显示金额（⌘⇧H）", isOn: Binding(
                    get: { controller.isMoneyVisible },
                    set: { controller.isMoneyVisible = $0 }
                ))
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 400, height: 620)
    }

    // MARK: - 组件

    private func row<Content: View>(
        _ title: String,
        unit: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 88, alignment: .leading)
            HStack(spacing: 6) {
                content()
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
        }
    }

    private func numberField(_ binding: Binding<Double>, width: CGFloat) -> some View {
        TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }

    /// 小时 + 分钟两个滚动选择器（macOS 没有 wheel 样式，用可滚动列表的 NSComboBox）
    private func timeWheels(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> some View {
        HStack(spacing: 3) {
            ScrollingNumberPicker(
                values: Array(0..<24),
                selection: hourBinding(keyPath),
                width: 58
            )
            Text(":")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            ScrollingNumberPicker(
                values: Array(stride(from: 0, to: 60, by: 5)),
                selection: minuteBinding(keyPath),
                width: 58
            )
        }
    }

    private func numberField(_ binding: Binding<Int>, width: CGFloat) -> some View {
        TextField("", value: binding, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }

    // MARK: - 绑定

    private func doubleBinding(_ keyPath: WritableKeyPath<SalaryConfig, Double>) -> Binding<Double> {
        Binding(
            get: { controller.config[keyPath: keyPath] },
            set: { controller.config[keyPath: keyPath] = $0 }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Int> {
        Binding(
            get: { controller.config[keyPath: keyPath] },
            set: { controller.config[keyPath: keyPath] = max($0, 0) }
        )
    }

    private func hourBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Int> {
        Binding(
            get: { controller.config[keyPath: keyPath] / 60 },
            set: { hour in
                let minute = controller.config[keyPath: keyPath] % 60
                controller.config[keyPath: keyPath] = min(max(hour, 0), 23) * 60 + minute
            }
        )
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Int> {
        Binding(
            get: {
                // 滑轮只列 5 的倍数；历史值不是整刻度时归一到最近的刻度
                let minute = controller.config[keyPath: keyPath] % 60
                return min(minute / 5 * 5, 55)
            },
            set: { minute in
                let hour = controller.config[keyPath: keyPath] / 60
                controller.config[keyPath: keyPath] = hour * 60 + min(max(minute, 0), 55)
            }
        )
    }
}


/// macOS 上没有 SwiftUI 的 `.wheel` 选择器；这里用可滚动的 `NSComboBox` 做等效控件：
/// 点开是一个可鼠标滚轮滚动的列表，选一项即生效。
struct ScrollingNumberPicker: NSViewRepresentable {
    let values: [Int]
    @Binding var selection: Int
    var width: CGFloat = 58

    final class Coordinator: NSObject {
        var values: [Int] = []
        var selection: Binding<Int>

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSComboBox) {
            let index = sender.indexOfSelectedItem
            guard index >= 0, index < values.count else { return }
            selection.wrappedValue = values[index]
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = false
        combo.completes = false
        combo.numberOfVisibleItems = 12
        combo.usesDataSource = false
        combo.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        combo.addItems(withObjectValues: values.map { String(format: "%02d", $0) })
        context.coordinator.values = values
        combo.target = context.coordinator
        combo.action = #selector(Coordinator.changed(_:))
        if let index = values.firstIndex(of: selection) {
            combo.selectItem(at: index)
        }
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.values = values
        context.coordinator.selection = $selection
        if let index = values.firstIndex(of: selection), combo.indexOfSelectedItem != index {
            combo.selectItem(at: index)
        }
    }
}
