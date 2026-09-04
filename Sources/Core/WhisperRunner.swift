import Foundation

struct WhisperOptions {
    /// "auto" for detection, or an ISO code such as "en", "zh", "de".
    var language: String = "auto"
    var translateToEnglish: Bool = false
    /// 4 = the M-series performance cores. Adding efficiency cores usually hurts.
    var threads: Int = 4
}

struct WhisperOutput {
    let segments: [Segment]
    let detectedLanguage: String?
    let usedNeuralEngine: Bool
}

enum WhisperRunner {
    private static let segmentPattern = try! NSRegularExpression(
        pattern: #"^\[(\d{2}):(\d{2}):(\d{2})\.(\d{3}) --> (\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)$"#)
    private static let progressPattern = try! NSRegularExpression(
        pattern: #"progress\s*=\s*(\d+)\s*%"#)
    private static let languagePattern = try! NSRegularExpression(
        pattern: #"auto-detected language:\s*([A-Za-z-]+)"#)

    /// Runs whisper-cli and parses its streams. Segments arrive on stdout;
    /// progress, language detection and Core ML status arrive on stderr.
    static func transcribe(
        wav: URL,
        layout: Layout,
        options: WhisperOptions,
        onProgress: ((Double) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil,
        registerHandle: ((RunningProcess) -> Void)? = nil
    ) throws -> WhisperOutput {
        var args = [
            "-m", layout.model.path,
            "-f", wav.path,
            "-t", String(options.threads),
            "-l", options.language,
            "-pp",
        ]
        if options.translateToEnglish { args.append("-tr") }

        // whisper-cli only ever reads; it needs no write access at all.
        let (exe, wrapped) = Sandbox.wrap(
            executable: layout.whisperCLI, arguments: args, writableDirs: [])

        var segments: [Segment] = []
        var language: String? = nil
        var coreMLLoaded = false
        var stderrTail: [String] = []

        func capture(_ s: String, _ re: NSRegularExpression, group: Int = 1) -> String? {
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: group), in: s) else { return nil }
            return String(s[r])
        }

        let status = try ProcessRunner.run(
            executable: exe,
            arguments: wrapped,
            onStdoutLine: { line in
                let range = NSRange(line.startIndex..., in: line)
                guard let m = Self.segmentPattern.firstMatch(in: line, range: range) else { return }
                func num(_ i: Int) -> Double {
                    guard let r = Range(m.range(at: i), in: line) else { return 0 }
                    return Double(line[r]) ?? 0
                }
                let start = num(1) * 3600 + num(2) * 60 + num(3) + num(4) / 1000
                let end = num(5) * 3600 + num(6) * 60 + num(7) + num(8) / 1000
                var text = ""
                if let r = Range(m.range(at: 9), in: line) { text = String(line[r]) }
                text = text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                segments.append(Segment(start: start, end: end, text: text))
            },
            onStderrLine: { line in
                if let pct = capture(line, Self.progressPattern), let v = Double(pct) {
                    onProgress?(min(max(v / 100, 0), 1))
                }
                if language == nil, let l = capture(line, Self.languagePattern) {
                    language = l
                }
                if line.contains("Core ML model loaded") { coreMLLoaded = true }
                stderrTail.append(line)
                if stderrTail.count > 60 { stderrTail.removeFirst() }
                onLog?(line)
            },
            registerHandle: registerHandle)

        guard status == 0 else {
            throw ProcessError(executable: "whisper-cli", exitCode: status,
                               stderrTail: stderrTail.suffix(15).joined(separator: "\n"))
        }
        // An explicitly requested language is not echoed back by whisper-cli.
        if language == nil && options.language != "auto" { language = options.language }
        return WhisperOutput(segments: segments, detectedLanguage: language,
                             usedNeuralEngine: coreMLLoaded)
    }
}
