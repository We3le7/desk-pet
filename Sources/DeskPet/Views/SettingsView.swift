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
                // 唯一保留的输入框，改成 AppKit 控件（SwiftUI 输入框会被 5Hz 刷新冲掉）
                row("税后月薪", unit: "元") {
                    MoneyTextField(value: doubleBinding(\.monthlyNet), width: 110)
                }
                row("月均工作日", unit: "天") {
                    ScrollingValuePicker(
                        values: steps(from: 20, through: 31, by: 0.25),
                        label: { String(format: "%.2f", $0) },
                        selection: doubleBinding(\.workdaysPerMonth),
                        width: 88
                    )
                }
                row("每日工时", unit: "小时") {
                    ScrollingValuePicker(
                        values: steps(from: 4, through: 14, by: 0.5),
                        label: { String(format: "%.1f", $0) },
                        selection: doubleBinding(\.hoursPerDay),
                        width: 88
                    )
                }
                row("年终额外月数", unit: "月") {
                    ScrollingValuePicker(
                        values: steps(from: 0, through: 6, by: 0.5),
                        label: { String(format: "%.1f", $0) },
                        selection: doubleBinding(\.extraMonthsPerYear),
                        width: 88
                    )
                }
                row("上班时间", unit: "") { timeWheels(\.startMinuteOfDay) }
                row("下班时间", unit: "") { timeWheels(\.endMinuteOfDay) }
                row("午休扣除", unit: "分钟") {
                    ScrollingValuePicker(
                        values: steps(from: 0, through: 180, by: 15),
                        label: { String(format: "%.0f", $0) },
                        selection: intFromDoubleBinding(\.lunchBreakMinutes),
                        width: 88
                    )
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
            ScrollingValuePicker(
                values: steps(from: 0, through: 23, by: 1),
                label: { String(format: "%02.0f", $0) },
                selection: hourDoubleBinding(keyPath),
                width: 58
            )
            Text(":")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            ScrollingValuePicker(
                values: steps(from: 0, through: 55, by: 5),
                label: { String(format: "%02.0f", $0) },
                selection: minuteDoubleBinding(keyPath),
                width: 58
            )
        }
    }

    private func hourDoubleBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(controller.config[keyPath: keyPath] / 60) },
            set: { hour in
                let minute = controller.config[keyPath: keyPath] % 60
                controller.config[keyPath: keyPath] = min(max(Int(hour.rounded()), 0), 23) * 60 + minute
            }
        )
    }

    private func minuteDoubleBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(controller.config[keyPath: keyPath] % 60) },
            set: { minute in
                let hour = controller.config[keyPath: keyPath] / 60
                controller.config[keyPath: keyPath] = hour * 60 + min(max(Int(minute.rounded()), 0), 55)
            }
        )
    }

    private func steps(from start: Double, through end: Double, by step: Double) -> [Double] {
        var values: [Double] = []
        var value = start
        while value <= end + 0.0001 {
            values.append((value * 100).rounded() / 100)
            value += step
        }
        return values
    }

    private func intFromDoubleBinding(_ keyPath: WritableKeyPath<SalaryConfig, Int>) -> Binding<Double> {
        Binding(
            get: { Double(controller.config[keyPath: keyPath]) },
            set: { controller.config[keyPath: keyPath] = Int($0.rounded()) }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<SalaryConfig, Double>) -> Binding<Double> {
        Binding(
            get: { controller.config[keyPath: keyPath] },
            set: { controller.config[keyPath: keyPath] = $0 }
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
    @ObservedObject private var preview = PetPreviewStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewPane

            Divider()

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
                VStack(alignment: .leading, spacing: 4) {
                    packRow(
                        id: PetThumbnail.builtinKey,
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
            .frame(maxHeight: 190)

            if catalog.packs.isEmpty {
                Text("没有发现宠物包，可放到 ~/.dsh/pets 或 ~/.codex/pets。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            preview.loadThumbnails(for: catalog.packs)
        }
        .onChange(of: catalog.packs.count) { _ in
            preview.loadThumbnails(for: catalog.packs)
        }
    }

    // MARK: - 预览

    private var previewPack: PetPack? {
        guard let hovered = preview.hoveredID else { return catalog.currentPack }
        if hovered == PetThumbnail.builtinKey { return nil }
        return catalog.packs.first { $0.id == hovered }
    }

    private var previewName: String {
        guard let hovered = preview.hoveredID else { return catalog.selectedName }
        if hovered == PetThumbnail.builtinKey { return "内置（代码绘制）" }
        return catalog.packs.first { $0.id == hovered }?.displayName ?? hovered
    }

    private var previewDetail: String {
        if let hovered = preview.hoveredID, hovered != PetThumbnail.builtinKey,
           let pack = catalog.packs.first(where: { $0.id == hovered }) {
            return "\(pack.tracks.count) 条轨道 · \(pack.license ?? "无许可声明")"
        }
        if preview.hoveredID == PetThumbnail.builtinKey {
            return "代码绘制，无外部素材"
        }
        if let pack = catalog.currentPack {
            return "\(pack.tracks.count) 条轨道 · \(pack.license ?? "无许可声明")"
        }
        return "代码绘制，无外部素材"
    }

    private var previewPane: some View {
        HStack(alignment: .center, spacing: 14) {
            PetPreviewView(pack: previewPack)
                .frame(width: 104, height: 136)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(previewName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(previewDetail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("悬停列表中的宠物即可预览形象")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private func packRow(id: String?, title: String, detail: String, selected: Bool) -> some View {
        Button {
            if id == PetThumbnail.builtinKey {
                catalog.select(nil)
            } else {
                catalog.select(id)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                thumbnail(for: id)
                    .frame(width: 26, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    Text(detail).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .font(.system(size: 12))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            preview.hoveredID = hovering ? (id ?? PetThumbnail.builtinKey) : nil
        }
    }

    @ViewBuilder
    private func thumbnail(for id: String?) -> some View {
        if let image = preview.thumbnail(for: id) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.08))
        }
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
