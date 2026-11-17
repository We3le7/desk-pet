import SwiftUI
import DeskPetCore

/// 设置面板：薪资、工时、暂停与金额显示。
struct SettingsView: View {
    @ObservedObject var controller: EarningsController

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
                    HStack(spacing: 4) {
                        numberField(hourBinding(\.startMinuteOfDay), width: 44)
                        Text("时").foregroundColor(.secondary)
                        numberField(minuteBinding(\.startMinuteOfDay), width: 44)
                        Text("分").foregroundColor(.secondary)
                    }
                }
                row("下班时间", unit: "") {
                    HStack(spacing: 4) {
                        numberField(hourBinding(\.endMinuteOfDay), width: 44)
                        Text("时").foregroundColor(.secondary)
                        numberField(minuteBinding(\.endMinuteOfDay), width: 44)
                        Text("分").foregroundColor(.secondary)
                    }
                }
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
        .frame(width: 380)
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
            get: { controller.config[keyPath: keyPath] % 60 },
            set: { minute in
                let hour = controller.config[keyPath: keyPath] / 60
                controller.config[keyPath: keyPath] = hour * 60 + min(max(minute, 0), 59)
            }
        )
    }
}
