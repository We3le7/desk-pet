import AppKit
import Foundation

/// 外观偏好：宠物大小、空闲轮播。
@MainActor
final class AppearanceStore: ObservableObject {
    @Published var petScale: CGFloat {
        didSet {
            defaults.set(Double(petScale), forKey: Self.scaleKey)
            onScaleChange?(petScale)
        }
    }
    @Published var rotateActions: Bool {
        didSet {
            defaults.set(rotateActions, forKey: Self.rotationKey)
            onRotationChange?(rotateActions)
        }
    }

    var onScaleChange: ((CGFloat) -> Void)?
    var onRotationChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private static let scaleKey = "appearance.petScale"
    private static let rotationKey = "appearance.rotateActions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedScale = defaults.object(forKey: Self.scaleKey) as? Double
        let storedRotation = defaults.object(forKey: Self.rotationKey) as? Bool
        self.petScale = CGFloat(min(max(storedScale ?? 1.0, 0.6), 2.0))
        self.rotateActions = storedRotation ?? true
    }
}
