import SwiftUI

// 主题配色：白布、灰蓝、浅棕、南瓜橙

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Palette {
    static let cloth = Color(hex: 0xF3F4F6)
    static let grayBlue = Color(hex: 0xA8B4CC)
    static let hemBlue = Color(hex: 0x9DBBE6)
    static let wood = Color(hex: 0xD9B48C)
    static let woodDark = Color(hex: 0xB48A5E)
    static let pumpkin = Color(hex: 0xE8913A)
    static let pumpkinDark = Color(hex: 0xC46E22)
    static let ink = Color(hex: 0x3F4656)
    static let face = Color(hex: 0x3A3D48)
    static let bandage = Color(hex: 0xF4EEE4)
    static let bandageEdge = Color(hex: 0xCFC2AC)

}

// MARK: - 形状

/// 带猫耳的白布幽灵，下摆撕得参差不齐
struct GhostShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        path.move(to: p(0.08, 0.46))
        path.addQuadCurve(to: p(0.13, 0.2), control: p(0.05, 0.3))
        path.addQuadCurve(to: p(0.37, 0.12), control: p(0.17, -0.06))
        path.addQuadCurve(to: p(0.63, 0.12), control: p(0.5, 0.06))
        path.addQuadCurve(to: p(0.87, 0.2), control: p(0.83, -0.06))
        path.addQuadCurve(to: p(0.92, 0.46), control: p(0.95, 0.3))
        path.addLine(to: p(0.97, 0.9))
        let hem: [(CGFloat, CGFloat)] = [
            (0.86, 0.98), (0.8, 0.88), (0.68, 1.0), (0.58, 0.9), (0.47, 0.99),
            (0.37, 0.87), (0.27, 0.97), (0.17, 0.88), (0.03, 0.95),
        ]
        for (x, y) in hem { path.addLine(to: p(x, y)) }
        path.closeSubpath()
        return path
    }
}

/// 下摆撕破的布条，用作白布便签
struct TornCloth: Shape {
    var seed: Int

    func path(in r: CGRect) -> Path {
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: seed))
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 6))
        var x = r.maxX
        while x > r.minX {
            x -= CGFloat.random(in: 7...15, using: &rng)
            let y = r.maxY - CGFloat.random(in: 0...12, using: &rng)
            path.addLine(to: CGPoint(x: max(x, r.minX), y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// 右下角折了一角的纸
struct DogEarPaper: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 14))
        path.addLine(to: CGPoint(x: r.maxX - 14, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.closeSubpath()
        return path
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
        return z ^ (z >> 33)
    }
}

// MARK: - 装饰小物件

/// 白布兜帽上的眯眼笑脸
struct HoodFace: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Ellipse().fill(Palette.face)
                    .frame(width: w * 0.13, height: h * 0.07)
                    .rotationEffect(.degrees(-22))
                    .position(x: w * 0.36, y: h * 0.36)
                Ellipse().fill(Palette.face)
                    .frame(width: w * 0.13, height: h * 0.07)
                    .rotationEffect(.degrees(22))
                    .position(x: w * 0.64, y: h * 0.36)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.42, y: h * 0.45))
                    p.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.45), control: CGPoint(x: w * 0.5, y: h * 0.53))
                }
                .stroke(Palette.face, style: StrokeStyle(lineWidth: max(1.2, w * 0.03), lineCap: .round))
                // 耳朵上的补丁
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.grayBlue.opacity(0.8))
                    .frame(width: w * 0.13, height: h * 0.1)
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h * 0.05)); p.addLine(to: CGPoint(x: w * 0.13, y: h * 0.05))
                            p.move(to: CGPoint(x: w * 0.065, y: 0)); p.addLine(to: CGPoint(x: w * 0.065, y: h * 0.1))
                        }.stroke(Palette.face.opacity(0.5), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 1.5]))
                    )
                    .rotationEffect(.degrees(12))
                    .position(x: w * 0.76, y: h * 0.14)
            }
        }
    }
}

/// 白布幽灵本体：兜帽笑脸 + 越往下越蓝的下摆
struct GhostBody: View {
    var body: some View {
        GhostShape()
            .fill(LinearGradient(stops: [
                .init(color: Palette.cloth, location: 0),
                .init(color: Palette.cloth, location: 0.55),
                .init(color: Palette.hemBlue, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .overlay(GhostShape().stroke(Palette.grayBlue.opacity(0.7), lineWidth: 1))
            .overlay(HoodFace())
    }
}

/// 晾衣夹：浅棕木头，固定的换成南瓜橙
struct Clothespin: View {
    var pinned: Bool

    var body: some View {
        let top = pinned ? Color(hex: 0xF2A65A) : Palette.wood
        let bottom = pinned ? Palette.pumpkinDark : Palette.woodDark
        ZStack {
            HStack(spacing: 1.2) {
                half(top, bottom)
                half(top, bottom)
            }
            Capsule()
                .stroke(Color(hex: 0x8E96A6), lineWidth: 1.6)
                .frame(width: 20, height: 6)
                .offset(y: -3)
        }
        .frame(width: 18, height: 40)
        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0.5, y: 1.5)
    }

    private func half(_ top: Color, _ bottom: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(bottom.opacity(0.8), lineWidth: 0.6))
            .frame(width: 8)
    }
}
