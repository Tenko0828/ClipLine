import AppKit
import Vision

/// 对一条记录做的“加工”：结果会作为新的文字卡片挂上绳子，并写进剪贴板
enum Transform: String, CaseIterable, Identifiable {
    case cleanWhitespace, oneLine
    case jsonPretty, jsonMinify
    case extractLinks
    case urlEncode, urlDecode
    case base64Encode, base64Decode
    case ocr
    case filePaths, fileNames

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanWhitespace: "清理多余空白"
        case .oneLine: "合并成一行"
        case .jsonPretty: "JSON 格式化"
        case .jsonMinify: "JSON 压缩"
        case .extractLinks: "提取链接"
        case .urlEncode: "URL 编码"
        case .urlDecode: "URL 解码"
        case .base64Encode: "Base64 编码"
        case .base64Decode: "Base64 解码"
        case .ocr: "识别图片文字"
        case .filePaths: "复制完整路径"
        case .fileNames: "复制文件名"
        }
    }

    static func available(for item: ClipItem) -> [Transform] {
        switch item.kind {
        case .text:
            let s = item.text ?? ""
            return allCases.filter { $0.isTextTransform && $0.textResult(s) != nil && $0.textResult(s) != s }
        case .image: return [.ocr]
        case .files: return [.filePaths, .fileNames]
        case .scene: return []
        }
    }

    private var isTextTransform: Bool {
        switch self {
        case .ocr, .filePaths, .fileNames: false
        default: true
        }
    }

    /// 文字类转换；不适用或失败时返回 nil
    func textResult(_ s: String) -> String? {
        switch self {
        case .cleanWhitespace:
            let lines = s.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            var out: [String] = []
            for l in lines where !(l.isEmpty && out.last?.isEmpty != false) { out.append(l) }
            let r = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return r.isEmpty ? nil : r
        case .oneLine:
            let r = s.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return r.isEmpty ? nil : r
        case .jsonPretty: return Self.json(s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .jsonMinify: return Self.json(s, options: [.sortedKeys, .withoutEscapingSlashes])
        case .extractLinks:
            guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
            var seen = Set<String>(), links: [String] = []
            for m in det.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                guard let u = m.url, u.scheme == "http" || u.scheme == "https" else { continue }
                if seen.insert(u.absoluteString).inserted { links.append(u.absoluteString) }
            }
            return links.isEmpty ? nil : links.joined(separator: "\n")
        case .urlEncode:
            return s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
        case .urlDecode:
            return s.contains("%") ? s.removingPercentEncoding : nil
        case .base64Encode:
            return Data(s.utf8).base64EncodedString()
        case .base64Decode:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 4, let d = Data(base64Encoded: t), let r = String(data: d, encoding: .utf8), !r.isEmpty else { return nil }
            return r
        default: return nil
        }
    }

    private static func json(_ s: String, options: JSONSerialization.WritingOptions) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") || t.hasPrefix("["),
              let obj = try? JSONSerialization.jsonObject(with: Data(t.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 文件类转换
    func fileResult(_ paths: [String]) -> String? {
        switch self {
        case .filePaths: paths.joined(separator: "\n")
        case .fileNames: paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n")
        default: nil
        }
    }

    /// 图片 OCR（中英文），在后台识别，结果回到主线程
    static func recognizeText(at url: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var result: String?
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(url: url)
            if (try? handler.perform([request])) != nil {
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                if !lines.isEmpty { result = lines.joined(separator: "\n") }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
