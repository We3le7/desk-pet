import AppKit
import DeskPetCore

/// 桌面悬浮宠物窗口：无边框、透明、置顶、全 Space 可见、永不抢焦点。
final class PetPanel: NSPanel {
    static let defaultSize = NSSize(width: 200, height: 260)
    private var displayView: PetDisplayView?
    private static let originKey = "pet.panel.origin"

    init() {
        let rect = NSRect(origin: .zero, size: Self.defaultSize)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false

        let container = DragContainerView(frame: rect)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let display = PetDisplayView(frame: container.bounds)
        display.autoresizingMask = [.width, .height]
        container.addSubview(display)
        displayView = display

        contentView = container
        applyRestoredPosition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - 位置

    private func applyRestoredPosition() {
        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = stored.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
                if isFullyVisibleOnSomeScreen() {
                    return
                }
            }
        }
        moveToDefaultCorner()
    }

    /// 必须整窗都在某个屏幕的可见区域内，否则视为失效（半截露在屏幕外也算）。
    private func isFullyVisibleOnSomeScreen() -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }

    /// 屏幕拔插、分辨率变化后把窗口拉回可见区。
    @objc private func handleScreenChange(_ note: Notification) {
        if !isFullyVisibleOnSomeScreen() {
            moveToDefaultCorner()
        } else {
            clampIntoVisibleArea()
        }
    }

    func clampIntoVisibleArea() {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        if origin != frame.origin {
            setFrameOrigin(origin)
            persistPosition()
        }
    }

    func moveToDefaultCorner() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - frame.width - 40,
            y: visible.minY + 60
        )
        setFrameOrigin(origin)
        persistPosition()
    }

    func persistPosition() {
        let value = "\(frame.origin.x),\(frame.origin.y)"
        UserDefaults.standard.set(value, forKey: Self.originKey)
    }

    func snapToNearestEdge(threshold: CGFloat = 24) {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = frame.origin

        if abs(origin.x - visible.minX) < threshold {
            origin.x = visible.minX
        } else if abs(visible.maxX - (origin.x + frame.width)) < threshold {
            origin.x = visible.maxX - frame.width
        }
        if abs(origin.y - visible.minY) < threshold {
            origin.y = visible.minY
        } else if abs(visible.maxY - (origin.y + frame.height)) < threshold {
            origin.y = visible.maxY - frame.height
        }

        if origin != frame.origin {
            setFrameOrigin(origin)
        }
        persistPosition()
    }

    // MARK: - 情绪

    func updateMood(_ mood: PetMood) {
        displayView?.setMood(mood)
    }

    func setPack(_ pack: PetPack?) {
        displayView?.setPack(pack)
    }

    func setMoneyText(_ text: String) {
        displayView?.setMoneyText(text)
    }

    func setMoneyVisible(_ visible: Bool) {
        displayView?.setMoneyVisible(visible)
    }

    func burstCoins(isBig: Bool) {
        displayView?.burstCoins(isBig: isBig)
    }

    // MARK: - 交互动作

    @objc func toggleClickThrough(_ sender: Any? = nil) {
        ignoresMouseEvents.toggle()
        if let item = sender as? NSMenuItem {
            item.state = ignoresMouseEvents ? .on : .off
        }
    }

    @objc func orderOutFromUser(_ sender: Any? = nil) {
        orderOut(nil)
    }

    @objc func resetPosition(_ sender: Any? = nil) {
        moveToDefaultCorner()
    }

    // MARK: - 右键菜单

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let clickThrough = NSMenuItem(
            title: "点击穿透",
            action: #selector(toggleClickThrough(_:)),
            keyEquivalent: ""
        )
        clickThrough.target = self
        clickThrough.state = ignoresMouseEvents ? .on : .off
        menu.addItem(clickThrough)

        let hide = NSMenuItem(title: "隐藏宠物", action: #selector(orderOutFromUser(_:)), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        let recenter = NSMenuItem(title: "回到右下角", action: #selector(resetPosition(_:)), keyEquivalent: "")
        recenter.target = self
        menu.addItem(recenter)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 DeskPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }
}

/// 接收全部鼠标事件的容器：SwiftUI 内容不参与 hit test，拖动由窗口自己处理。
final class DragContainerView: NSView {
    private var mouseDownLocation: NSPoint = .zero
    private var windowOriginAtMouseDown: NSPoint = .zero
    private var didDrag = false

    /// 让所有点击都落到容器上，避免被 NSHostingView 吃掉。
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        if abs(dx) > 2 || abs(dy) > 2 { didDrag = true }
        window.setFrameOrigin(
            NSPoint(x: windowOriginAtMouseDown.x + dx, y: windowOriginAtMouseDown.y + dy)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard let panel = window as? PetPanel else { return }
        panel.snapToNearestEdge()
        panel.persistPosition()
        _ = didDrag
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let panel = window as? PetPanel else { return }
        let menu = panel.makeContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
