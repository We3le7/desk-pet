import AppKit
import SwiftUI
import DeskPetCore

/// 调试面板：1Hz 刷新的一排数值，用来核对采集是否与系统工具一致。
struct DebugPanelView: View {
    @ObservedObject var state: PetAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DeskPet 指标")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(state.updatedAtText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Divider()

            row("情绪", state.moodText, highlight: true)
            row("CPU", state.cpuText)
            row("内存", state.memoryText)
            row("电池", state.batteryText)
            row("网络", state.networkText)
            row("磁盘", state.diskText)
            row("热压力", state.thermalText)
            row("前台应用", state.frontmostText)

            Divider()

            Text("1Hz 采样 · 零权限 · 全部公开 API")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func row(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: highlight ? .semibold : .regular).monospacedDigit())
                .foregroundColor(highlight ? .accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}
