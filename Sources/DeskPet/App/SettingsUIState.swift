import Foundation

enum SettingsTab: Hashable {
    case earnings
    case pet
}

/// 设置窗口的标签页选中状态（CLT 下 SwiftUI 的状态属性不可用，所以放在可观察对象里）。
@MainActor
final class SettingsUIState: ObservableObject {
    @Published var tab: SettingsTab

    init(tab: SettingsTab = .pet) {
        self.tab = tab
    }
}
