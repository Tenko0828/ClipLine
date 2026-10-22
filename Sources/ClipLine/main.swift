import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// 用 Carbon 注册全局快捷键，不需要辅助功能权限
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C_4C4E), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ClipboardStore()
    lazy var controller = LineController(store: store)
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let menu = NSMenu()
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不让系统 App Nap 把轮询剪贴板的定时器睡掉
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "监听剪贴板")
        store.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusIcon()
        statusItem.button?.toolTip = "晾衣绳剪贴板（⌥⌘V）"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        menu.delegate = self

        // ⌥⌘V
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.controller.toggle()
        }

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.controller.show() }
        }
    }

    @objc private func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            controller.toggle()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("打开晾衣绳", #selector(openLine), key: "v", mods: [.command, .option]))
        menu.addItem(item("把当前桌面存成场景…", #selector(saveScene)))
        menu.addItem(.separator())
        menu.addItem(item("取用后自动粘贴", #selector(toggleAutoPaste), on: controller.autoPaste))
        menu.addItem(item("开机时启动", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("清空（保留固定的）", #selector(clearAll)))
        menu.addItem(item("打开存储文件夹", #selector(openFolder)))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit), key: "q", mods: [.command]))
    }

    private func item(_ title: String, _ sel: Selector, key: String = "", mods: NSEvent.ModifierFlags = [], on: Bool = false) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.keyEquivalentModifierMask = mods
        mi.target = self
        mi.state = on ? .on : .off
        return mi
    }

    @objc private func openLine() { controller.show() }

    @objc private func toggleAutoPaste() {
        controller.autoPaste.toggle()
        if controller.autoPaste {
            // 模拟 ⌘V 需要辅助功能权限，这里弹系统授权提示
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "没能设置开机启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func saveScene() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "把当前打开的 App 和 Finder 文件夹存成场景"
        alert.informativeText = "之后在绳子上点这张卡片，就能把它们重新打开。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "场景名，比如“写代码”"
        alert.accessoryView = field
        alert.addButton(withTitle: "存下来")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        store.addScene(SceneTool.capture(name: name.isEmpty ? "未命名场景" : name))
    }

    @objc private func clearAll() { store.clearUnpinned() }
    @objc private func openFolder() { NSWorkspace.shared.open(store.dir) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// 菜单栏图标：一只带猫耳的小幽灵
    static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { r in
            let path = GhostShape().path(in: r.insetBy(dx: 2, dy: 1.5)).cgPath
            let bp = NSBezierPath(cgPath: path)
            NSColor.black.setStroke()
            bp.lineWidth = 1.4
            bp.lineJoinStyle = .round
            bp.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.2, y: 7, width: 1.8, height: 2.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 7, width: 1.8, height: 2.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

extension NSBezierPath {
    convenience init(cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { el in
            let p = el.pointee.points
            switch el.pointee.type {
            case .moveToPoint: move(to: p[0])
            case .addLineToPoint: line(to: p[0])
            case .addQuadCurveToPoint:
                let c1 = CGPoint(x: currentPoint.x + 2 / 3 * (p[0].x - currentPoint.x), y: currentPoint.y + 2 / 3 * (p[0].y - currentPoint.y))
                let c2 = CGPoint(x: p[1].x + 2 / 3 * (p[0].x - p[1].x), y: p[1].y + 2 / 3 * (p[0].y - p[1].y))
                curve(to: p[1], controlPoint1: c1, controlPoint2: c2)
            case .addCurveToPoint: curve(to: p[2], controlPoint1: p[0], controlPoint2: p[1])
            case .closeSubpath: close()
            @unknown default: break
            }
        }
    }
}

/// 构建脚本用：把 App 图标渲染成 PNG
@MainActor func renderIcon(to path: String) {
    let view = ZStack {
        RoundedRectangle(cornerRadius: 185, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFCE6CC), Palette.pumpkin], startPoint: .top, endPoint: .bottom))
        Path { p in
            p.move(to: CGPoint(x: 60, y: 250))
            p.addQuadCurve(to: CGPoint(x: 964, y: 250), control: CGPoint(x: 512, y: 420))
        }
        .stroke(Palette.bandage, style: StrokeStyle(lineWidth: 34, lineCap: .round))
        GhostBody()
            .frame(width: 560, height: 650)
            .offset(y: 130)
        Clothespin(pinned: false)
            .scaleEffect(5)
            .offset(y: -150)
    }
    .frame(width: 1024, height: 1024)
    .scaleEffect(824.0 / 1024)
    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    .frame(width: 1024, height: 1024)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { renderIcon(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

/// 安装脚本用：把自己注册为开机启动项
if CommandLine.arguments.contains("--enable-login-item") {
    do {
        if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        print("login item:", SMAppService.mainApp.status == .enabled ? "enabled" : "status \(SMAppService.mainApp.status.rawValue)")
        exit(0)
    } catch {
        print("login item failed:", error.localizedDescription)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
