import AppKit
import SwiftUI

final class LinePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 管理挂在屏幕顶端的那块透明浮窗：显示/收起、滚动、键盘
final class LineController: NSObject, NSWindowDelegate {
    let store: ClipboardStore
    let model = LineModel()
    private let panel: LinePanel
    private var monitors: [Any] = []
    private var generation = 0

    var autoPaste: Bool {
        get { UserDefaults.standard.bool(forKey: "autoPaste") }
        set { UserDefaults.standard.set(newValue, forKey: "autoPaste") }
    }

    init(store: ClipboardStore) {
        self.store = store
        panel = LinePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 盖在菜单栏上面，绳子才像是从屏幕顶上挂下来的
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LineView(store: store, model: model))

        model.onPick = { [weak self] in self?.pick($0) }
        model.onDismiss = { [weak self] in self?.hide() }
        model.onTransform = { [weak self] t, item in self?.transform(t, item) }
    }

    var isShown: Bool { panel.isVisible && model.visible }

    func toggle() { isShown ? hide() : show() }

    func show() {
        generation += 1
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let h = Layout.panelHeight
        panel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h), display: false)

        model.offset = 0
        model.selected = store.items.isEmpty ? nil : 0
        model.copiedID = nil
        panel.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) { model.visible = true }
        model.showToken += 1
        installMonitors()
    }

    func hide() {
        guard panel.isVisible, model.visible else { return }
        generation += 1
        let gen = generation
        removeMonitors()
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel.orderOut(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - 取用

    private func pick(_ item: ClipItem) {
        guard model.copiedID == nil else { return }
        store.copyToPasteboard(item)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { model.copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self else { return }
            self.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.model.copiedID = nil
                self.store.bump(item.id)
                if self.autoPaste { Self.simulatePaste() }
            }
        }
    }

    private func transform(_ t: Transform, _ item: ClipItem) {
        store.applyTransform(t, to: item) { [weak self] ok in
            guard let self else { return }
            if !ok { NSSound.beep(); return }
            self.hide()
            if self.autoPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Self.simulatePaste() }
            }
        }
    }

    static func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - 滚动、键盘、点外面收起

    private var viewWidth: CGFloat { panel.frame.width }

    private var maxOffset: CGFloat {
        max(0, Layout.contentWidth(count: store.items.count, viewWidth: viewWidth) - viewWidth)
    }

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 14
            let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
            self.model.offset = min(max(0, self.model.offset - d * scale), self.maxOffset)
            return nil
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.handleKey(e) ? nil : e
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        let items = store.displayItems
        switch e.keyCode {
        case 53: hide(); return true                                  // Esc
        case 123: select((model.selected ?? 0) - 1); return true      // ←
        case 124: select((model.selected ?? -1) + 1); return true     // →
        case 36, 76:                                                   // Return
            if let i = model.selected, items.indices.contains(i) { pick(items[i]) }
            return true
        case 51, 117:                                                  // Delete
            if let i = model.selected, items.indices.contains(i) {
                store.delete(items[i].id)
                model.selected = store.items.isEmpty ? nil : min(i, store.items.count - 1)
            }
            return true
        default:
            if let c = e.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n), items.indices.contains(n - 1) {
                select(n - 1)
                pick(items[n - 1])
                return true
            }
            return false
        }
    }

    private func select(_ i: Int) {
        let n = store.items.count
        guard n > 0 else { return }
        let idx = min(max(i, 0), n - 1)
        model.selected = idx
        let width = Layout.contentWidth(count: n, viewWidth: viewWidth)
        let x = Layout.x(index: idx, count: n, width: width)
        var off = model.offset
        if x - off < 160 { off = x - 160 }
        if x - off > viewWidth - 160 { off = x - viewWidth + 160 }
        off = min(max(0, off), maxOffset)
        withAnimation(.easeOut(duration: 0.25)) { model.offset = off }
    }
}
