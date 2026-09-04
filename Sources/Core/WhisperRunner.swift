import Foundation

public struct WhisperOptions {
    /// "auto" for detection, or an ISO code such as "en", "zh", "de".
    public var language: String = "auto"
    public var translateToEnglish: Bool = false
    /// 4 = the M-series performance cores. Adding efficiency cores usually hurts.
    public var threads: Int = 4
    /// Let the decoder carry text forward as context between its internal
    /// 30-second windows.
    ///
    /// This is on by default because it is what produces correct punctuation and
    /// consistent spelling: without it the model restarts cold every 30 seconds,
    /// often mid-sentence, and no longer knows a sentence is in progress.
    ///
    /// It does carry a risk — the decoder can lock into repeating one sentence,
    /// and the carried text feeds that loop. We contain that with chunk
    /// boundaries at natural pauses rather than by disabling this, so the quality
    /// cost is paid only where a speaker had genuinely stopped talking.
    public var carryContext: Bool = true

    public init() {}
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
    /// Transcribes `wav`, optionally only the range starting at `offset` and
    /// running for `duration`. Timestamps come back measured from the start of
    /// the file, not the start of the range, so ranges need no rebasing.
    static func transcribe(
        wav: URL,
        layout: Layout,
        options: WhisperOptions,
        offset: TimeInterval = 0,
        duration: TimeInterval? = nil,
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
        if offset > 0 { args += ["-ot", String(Int(offset * 1000))] }
        if let duration { args += ["-d", String(Int(duration * 1000))] }
        if options.translateToEnglish { args.append("-tr") }
        if !options.carryContext { args += ["-mc", "0"] }

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
