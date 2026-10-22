import AppKit
import SwiftUI

/// 一个“场景”：当时打开着的 App 和 Finder 文件夹，点一下就能恢复
struct SceneData: Codable, Equatable {
    var name: String
    var apps: [String]      // bundle id
    var folders: [String]   // 路径
}

enum SceneTool {
    private static let skippedApps: Set<String> = ["com.apple.finder", "local.tenko.clipline"]

    /// 抓取当前桌面：普通 App + Finder 里打开的文件夹窗口
    static func capture(name: String) -> SceneData {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap(\.bundleIdentifier)
            .filter { !skippedApps.contains($0) }
        return SceneData(name: name, apps: apps, folders: finderFolders())
    }

    /// 通过 AppleScript 读 Finder 窗口（首次会弹“自动化”授权），失败就当没有
    private static func finderFolders() -> [String] {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.finder" }) else { return [] }
        let src = """
        tell application "Finder"
            set out to {}
            repeat with w in (every Finder window)
                try
                    set end of out to POSIX path of (target of w as alias)
                end try
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let desc = NSAppleScript(source: src)?.executeAndReturnError(&err), err == nil else { return [] }
        var paths: [String] = []
        if desc.numberOfItems > 0 {
            for i in 1...desc.numberOfItems {
                if let p = desc.atIndex(i)?.stringValue, !paths.contains(p) { paths.append(p) }
            }
        } else if let p = desc.stringValue, !p.isEmpty { paths.append(p) }
        return paths
    }

    /// 恢复：把没开的 App 启动起来，打开文件夹。已经开着的不动，也不会关掉别的东西
    static func restore(_ scene: SceneData) {
        let ws = NSWorkspace.shared
        let running = Set(ws.runningApplications.compactMap(\.bundleIdentifier))
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        for id in scene.apps where !running.contains(id) {
            guard let url = ws.urlForApplication(withBundleIdentifier: id) else { continue }
            ws.openApplication(at: url, configuration: cfg)
        }
        for path in scene.folders where FileManager.default.fileExists(atPath: path) {
            ws.open(URL(fileURLWithPath: path))
        }
    }

    static func icon(forBundleID id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

struct SceneCard: View {
    let scene: SceneData
    let date: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(scene.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            let ids = Array(scene.apps.prefix(6))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 3), spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    if let img = SceneTool.icon(forBundleID: id) {
                        Image(nsImage: img).resizable().frame(width: 28, height: 28)
                    }
                }
            }
            Text("\(scene.apps.count) 个 App" + (scene.folders.isEmpty ? "" : " · \(scene.folders.count) 个文件夹"))
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Palette.ink.opacity(0.6))
            Spacer(minLength: 0)
            Text(relativeTime(date))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Palette.ink.opacity(0.5))
        }
        .padding(EdgeInsets(top: 26, leading: 10, bottom: 9, trailing: 10))
        .frame(width: Layout.cardW, height: 140)
        .background(DogEarPaper().fill(Color(hex: 0xD9E8D2)))
    }
}
