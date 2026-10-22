import SwiftUI

final class LineModel: ObservableObject {
    @Published var visible = false
    @Published var showToken = 0
    @Published var offset: CGFloat = 0
    @Published var selected: Int?
    @Published var copiedID: UUID?

    var onPick: ((ClipItem) -> Void)?
    var onDismiss: (() -> Void)?
    var onTransform: ((Transform, ClipItem) -> Void)?
}

enum Layout {
    static let panelHeight: CGFloat = 310
    static let spacing: CGFloat = 178
    /// 两端留白，右端给白布幽灵
    static let pad: CGFloat = 150
    static let cardW: CGFloat = 148

    static func contentWidth(count: Int, viewWidth: CGFloat) -> CGFloat {
        max(viewWidth, pad * 2 + spacing * CGFloat(max(count, 1)))
    }

    /// 东西少的时候居中挂，多了就从左往右排、可以横向滚动
    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let start = max(pad, (width - spacing * CGFloat(count)) / 2)
        return start + spacing * (CGFloat(index) + 0.5)
    }
}

/// 两端系在屏幕顶上、中间往下坠的绳子
struct Rope {
    let width: CGFloat
    let y0: CGFloat = 12
    var sag: CGFloat { min(78, width * 0.05) }

    func y(_ x: CGFloat) -> CGFloat {
        let t = x / width
        return y0 + sag * 4 * t * (1 - t)
    }

    func slope(_ x: CGFloat) -> CGFloat {
        sag * 4 * (1 - 2 * x / width) / width
    }
}

struct LineView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: LineModel

    var body: some View {
        GeometryReader { geo in
            let items = store.displayItems
            let width = Layout.contentWidth(count: items.count, viewWidth: geo.size.width)
            let rope = Rope(width: width)

            ZStack(alignment: .topLeading) {
                // 背景原地淡入淡出，不跟着绳子移动，顶部就不会露出空缺
                Backdrop()
                    .opacity(model.visible ? 1 : 0)
                    .onTapGesture { model.onDismiss?() }

                ZStack(alignment: .topLeading) {
                    BandageRope(rope: rope, offset: model.offset)
                        .allowsHitTesting(false)

                    if items.isEmpty {
                        EmptyNote()
                            .offset(x: width / 2 - model.offset - Layout.cardW / 2, y: rope.y(width / 2) - 14)
                    }

                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        let x = Layout.x(index: i, count: items.count, width: width)
                        let tangent = atan(rope.slope(x)) * 180 / .pi
                        HangingCard(item: item, index: i, angle: item.tilt + tangent * 0.6, model: model, store: store)
                            .offset(x: x - model.offset - Layout.cardW / 2, y: rope.y(x) - 14)
                    }

                    GhostOnRope()
                        .allowsHitTesting(false)
                        .offset(x: width - 80 - model.offset - 36, y: rope.y(width - 80) - 30)
                }
                .offset(y: model.visible ? 0 : -geo.size.height)

                HintBar()
                    .frame(width: geo.size.width)
                    .offset(y: geo.size.height - 36)
                    .opacity(model.visible ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

// MARK: - 背景、绳子

struct Backdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [Color(hex: 0x2B3245, alpha: 0.45), Color(hex: 0x2B3245, alpha: 0.18), .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .contentShape(Rectangle())
    }
}

/// 绳子画成一条绷带：一圈圈缠绕的线，右端的绷带头垂下来
struct BandageRope: View {
    let rope: Rope
    let offset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            ctx.translateBy(x: -offset, y: 0)
            let x0 = max(0, offset - 20)
            let x1 = min(rope.width, offset + size.width + 20)

            var main = Path()
            var pts: [CGPoint] = []
            var x = x0
            while x < x1 { pts.append(CGPoint(x: x, y: rope.y(x))); x += 3 }
            pts.append(CGPoint(x: x1, y: rope.y(x1)))
            main.addLines(pts)

            var tail = Path()
            if x1 >= rope.width - 1 {
                let w = rope.width
                tail.move(to: CGPoint(x: w - 6, y: rope.y0 + 1))
                tail.addCurve(to: CGPoint(x: w - 22, y: 168),
                              control1: CGPoint(x: w + 10, y: 70),
                              control2: CGPoint(x: w - 44, y: 110))
            }

            for p in [main, tail] {
                ctx.stroke(p.offsetBy(dx: 1, dy: 3), with: .color(.black.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(Palette.bandageEdge),
                           style: StrokeStyle(lineWidth: 9, lineCap: .butt, lineJoin: .round))
                ctx.stroke(p, with: .color(Palette.bandage),
                           style: StrokeStyle(lineWidth: 7, lineCap: .butt, lineJoin: .round))
            }

            // 绷带的缠绕纹，按绝对 x 对齐，滚动时不会闪
            var marks = Path()
            var mx = (x0 / 12).rounded(.down) * 12
            while mx < x1 {
                let y = rope.y(mx)
                marks.move(to: CGPoint(x: mx - 2.5, y: y - 3.4))
                marks.addLine(to: CGPoint(x: mx + 2.5, y: y + 3.4))
                mx += 12
            }
            ctx.stroke(marks, with: .color(Palette.bandageEdge), lineWidth: 1)

            // 左端的钉子
            if x0 <= 1 {
                let nail = CGRect(x: 2, y: rope.y0 - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: nail), with: .color(Color(hex: 0x8E96A6)))
                ctx.fill(Path(ellipseIn: nail.insetBy(dx: 2.5, dy: 2.5)), with: .color(Color(hex: 0xC9CED8)))
            }
        }
    }
}

/// 绳子右端的白布幽灵，两只小手搭在绷带上
struct GhostOnRope: View {
    var body: some View {
        ZStack(alignment: .top) {
            GhostBody()
                .frame(width: 72, height: 84)
                .offset(y: 10)
            // 搭在绳子上的小手
            HStack(spacing: 30) {
                hand
                hand
            }
            .offset(y: 26)
        }
        .frame(width: 72, height: 100)
    }

    private var hand: some View {
        Circle().fill(Palette.cloth)
            .overlay(Circle().stroke(Palette.grayBlue, lineWidth: 0.8))
            .frame(width: 11)
    }
}

struct HintBar: View {
    var body: some View {
        HStack {
            Spacer()
            Text("点击取用 · 拖出去 · 右键固定/删除 · ← → ⏎ · 1-9 快选 · Esc 收起")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: 0x2B3245, alpha: 0.45)))
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 卡片

struct HangingCard: View {
    let item: ClipItem
    let index: Int
    let angle: Double
    @ObservedObject var model: LineModel
    let store: ClipboardStore

    @State private var swing: Double = 0
    @State private var hovering = false

    private var isSelected: Bool { model.selected == index }
    private var lifted: Bool { hovering || isSelected }

    var body: some View {
        VStack(spacing: -24) {
            Clothespin(pinned: item.pinned).zIndex(1)
            content
                .overlay(alignment: .topLeading) { badge }
                .overlay {
                    if model.copiedID == item.id {
                        CopiedStamp().transition(.scale(scale: 2).combined(with: .opacity))
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3).stroke(Palette.pumpkin.opacity(0.9), lineWidth: 2)
                            .padding(-3)
                    }
                }
                .shadow(color: .black.opacity(lifted ? 0.35 : 0.22), radius: lifted ? 10 : 5, x: 2, y: lifted ? 8 : 4)
        }
        .frame(width: Layout.cardW)
        .scaleEffect(lifted ? 1.05 : 1, anchor: .top)
        .rotationEffect(.degrees(angle + swing), anchor: UnitPoint(x: 0.5, y: 0.04))
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
            if h { kick(Double.random(in: 2.5...4) * (Bool.random() ? 1 : -1)) }
        }
        .onTapGesture { model.onPick?(item) }
        .onDrag { store.itemProvider(for: item) }
        .contextMenu {
            Button("取用") { model.onPick?(item) }
            Button(item.pinned ? "取消固定" : "固定在绳子上") { store.togglePin(item.id) }
            let transforms = Transform.available(for: item)
            if !transforms.isEmpty {
                Menu("加工…") {
                    ForEach(transforms) { t in
                        Button(t.title) { model.onTransform?(t, item) }
                    }
                }
            }
            Divider()
            Button("取下来（删除）") { store.delete(item.id) }
        }
        .help(helpText)
        .onChange(of: model.showToken) { _ in
            kick(Double.random(in: 7...12) * (index.isMultiple(of: 2) ? 1 : -1), delay: 0.12 + Double(index) * 0.04)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text: NoteCard(text: item.text ?? "", date: item.date, seed: Int(item.id.uuid.0) << 8 | Int(item.id.uuid.1))
        case .image: PhotoCard(image: store.thumbnail(for: item), size: item.imageSize, date: item.date)
        case .files: FileTag(paths: item.filePaths ?? [], date: item.date)
        }
    }

    @ViewBuilder private var badge: some View {
        if index < 9 {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 15, height: 15)
                .background(Circle().fill(Palette.grayBlue))
                .padding(6)
        }
    }

    private var helpText: String {
        switch item.kind {
        case .text: String((item.text ?? "").prefix(600))
        case .image: "图片 \(Int(item.imageSize?.width ?? 0))×\(Int(item.imageSize?.height ?? 0))"
        case .files: (item.filePaths ?? []).joined(separator: "\n")
        }
    }

    /// 推一下，让卡片像挂在绳子上一样晃几下再停
    private func kick(_ amount: Double, delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.14)) { swing = amount }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
            }
        }
    }
}

struct NoteCard: View {
    let text: String
    let date: Date
    let seed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let host = linkHost {
                Text("🔗 \(host)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.pumpkinDark)
                    .lineLimit(1)
                    .padding(.bottom, 3)
            }
            Text(preview)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Palette.ink)
                .lineSpacing(2)
                .lineLimit(linkHost == nil ? 7 : 6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 4)
            HStack {
                Text(relativeTime(date))
                Spacer()
                Text(verbatim: "\(text.count) 字")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(Palette.ink.opacity(0.5))
            .padding(.bottom, 8)
        }
        .padding(EdgeInsets(top: 24, leading: 12, bottom: 10, trailing: 12))
        .frame(width: Layout.cardW, height: 152, alignment: .topLeading)
        .background(background)
    }

    private var background: some View {
        TornCloth(seed: seed)
            .fill(LinearGradient(stops: [
                .init(color: Palette.cloth, location: 0),
                .init(color: Palette.cloth, location: 0.62),
                .init(color: Palette.hemBlue.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom))
    }

    private var preview: String {
        let lines = text.prefix(500)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private var linkHost: String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: \.isWhitespace), let url = URL(string: s),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.host
    }
}

struct PhotoCard: View {
    let image: NSImage?
    let size: CGSize?
    let date: Date

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Palette.grayBlue.opacity(0.3)
                }
            }
            .frame(width: Layout.cardW - 16, height: 120)
            .clipped()
            HStack {
                Text(verbatim: size.map { "\(Int($0.width))×\(Int($0.height))" } ?? "图片")
                Spacer()
                Text(relativeTime(date))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(Palette.ink.opacity(0.5))
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 9, trailing: 8))
        .frame(width: Layout.cardW)
        .background(Color(hex: 0xFCFCFD))
    }
}

struct FileTag: View {
    let paths: [String]
    let date: Date

    var body: some View {
        VStack(spacing: 5) {
            if let first = paths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                    .resizable()
                    .frame(width: 50, height: 50)
                Text((first as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if paths.count > 1 {
                Text("等 \(paths.count) 个文件")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(Palette.ink.opacity(0.6))
            }
            Spacer(minLength: 0)
            Text(relativeTime(date))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Palette.ink.opacity(0.5))
        }
        .padding(EdgeInsets(top: 26, leading: 10, bottom: 9, trailing: 10))
        .frame(width: Layout.cardW, height: 140)
        .background(DogEarPaper().fill(Color(hex: 0xEED9BA)))
    }
}

struct EmptyNote: View {
    var body: some View {
        VStack(spacing: -24) {
            Clothespin(pinned: false).zIndex(1)
            Text("还没有剪贴内容\n复制点什么就会挂上来")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Palette.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(EdgeInsets(top: 24, leading: 12, bottom: 12, trailing: 12))
                .frame(width: Layout.cardW, height: 110)
                .background(TornCloth(seed: 7).fill(LinearGradient(colors: [Palette.cloth, Palette.cloth, Palette.hemBlue],
                                                                    startPoint: .top, endPoint: .bottom)))
                .shadow(color: .black.opacity(0.22), radius: 5, x: 2, y: 4)
        }
    }
}

struct CopiedStamp: View {
    var body: some View {
        Text("已复制")
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundColor(Palette.pumpkin)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.pumpkin, lineWidth: 2.5))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.75)))
            .rotationEffect(.degrees(-14))
    }
}

func relativeTime(_ date: Date) -> String {
    let s = Date().timeIntervalSince(date)
    switch s {
    case ..<60: return "刚刚"
    case ..<3600: return "\(Int(s / 60)) 分钟前"
    case ..<86400: return "\(Int(s / 3600)) 小时前"
    default: return "\(Int(s / 86400)) 天前"
    }
}
