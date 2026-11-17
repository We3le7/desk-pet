import AppKit
import SwiftUI
import DeskPetCore

/// 设置窗口：两个标签页 —— 上班鼓励器 / 宠物。
struct SettingsView: View {
    @ObservedObject var controller: EarningsController
    @ObservedObject var appearance: AppearanceStore
    @ObservedObject var catalog: PetsCatalog
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        TabView(selection: $ui.tab) {
            EarningsSettingsView(controller: controller)
                .tabItem { Text("上班鼓励器") }
                .tag(SettingsTab.earnings)

            PetSettingsView(appearance: appearance, catalog: catalog)
                .tabItem { Text("宠物") }
                .tag(SettingsTab.pet)
        }
        .padding(16)
        .frame(width: 420, height: 600)
    }
}

// MARK: - 上班鼓励器

struct EarningsSettingsView: View {
    @ObservedObject var controller: EarningsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("税后月薪", unit: "元") { numberField(doubleBinding(\.monthlyNet), width: 88) }
                row("月均工作日", unit: "天") { numberField(doubleBinding(\.workdaysPerMonth), width: 88) }
                row("每日工时", unit: "小时") { numberField(doubleBinding(\.hoursPerDay), width: 88) }
                row("年终额外月数", unit: "月") { numberField(doubleBinding(\.extraMonthsPerYear), width: 88) }
                row("上班时间", unit: "") { timeWheels(\.startMinuteOfDay) }
                row("下班时间", unit: "") { timeWheels(\.endMinuteOfDay) }
                row("午休扣除", unit: "分钟") { numberField(intBinding(\.lunchBreakMinutes), width: 88) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.config.summary)
                    .font(.system(size: 12).monospacedDigit())
                Text("今日已到账 \(MoneyFormat.yuan(controller.amount.total))"
                     + (controller.isPaused ? "（已暂停）" : ""))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
                Text("按在岗时长计钱：合同时薪 × 在岗秒数。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 14) {
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
    }

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

    private func timeWheels(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> some View {
        HStack(spacing: 3) {
            ScrollingNumberPicker(values: Array(0..<24), selection: hourBinding(keyPath), width: 58)
            Text(":")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            ScrollingNumberPicker(values: Array(stride(from: 0, to: 60, by: 5)), selection: minuteBinding(keyPath), width: 58)
        }
    }

    private func numberField(_ binding: Binding<Double>, width: CGFloat) -> some View {
        TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }

    private func numberField(_ binding: Binding<Int>, width: CGFloat) -> some View {
        TextField("", value: binding, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }

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

// MARK: - 宠物

struct PetSettingsView: View {
    @ObservedObject var appearance: AppearanceStore
    @ObservedObject var catalog: PetsCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("在桌面上显示宠物", isOn: Binding(
                get: { appearance.isPetVisible },
                set: { appearance.isPetVisible = $0 }
            ))
            .toggleStyle(.switch)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("大小").font(.system(size: 12)).foregroundColor(.secondary)
                        .frame(width: 88, alignment: .leading)
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { appearance.petScale },
                                set: { appearance.petScale = $0 }
                            ),
                            in: 0.6...2.0,
                            step: 0.05
                        )
                        .frame(width: 170)
                        Text(String(format: "%.0f%%", appearance.petScale * 100))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
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

            Text("皮肤")
                .font(.system(size: 13, weight: .semibold))
            Text("当前：\(catalog.selectedName)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    packRow(
                        id: nil,
                        title: "内置（代码绘制）",
                        detail: "不需要素材，任何机器上都有",
                        selected: catalog.selectedID == nil
                    )
                    ForEach(catalog.packs, id: \.id) { pack in
                        packRow(
                            id: pack.id,
                            title: pack.displayName,
                            detail: "\(pack.id) · \(pack.tracks.count) 轨 · \(pack.license ?? "无许可声明")",
                            selected: catalog.selectedID == pack.id
                        )
                    }
                }
            }
            .frame(maxHeight: 230)

            if catalog.packs.isEmpty {
                Text("没有发现宠物包，可放到 ~/.dsh/pets 或 ~/.codex/pets。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func packRow(id: String?, title: String, detail: String, selected: Bool) -> some View {
        Button {
            catalog.select(id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    Text(detail).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 可滚动数字选择器

/// macOS 上没有 SwiftUI 的 `.wheel` 选择器；这里用可滚动的 `NSComboBox` 做等效控件。
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
