import Foundation

struct TranscriptionRequest {
    let source: URL
    var options = WhisperOptions()
    /// Keep the intermediate 16 kHz WAV instead of removing it on success.
    var keepIntermediateWAV = false
    /// Overwrite an existing .md rather than picking the next free name.
    var overwrite = false
}

enum Stage {
    case inspecting
    case converting
    case transcribing(Double)   // 0...1
    case writing
}

enum TranscriberError: LocalizedError {
    case noSpeech(URL)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSpeech(let u): return "No speech was found in \(u.lastPathComponent)."
        case .cancelled: return "Cancelled."
        }
    }
}

enum Transcriber {
    /// Marker that makes our intermediate file obvious in Finder next to the original.
    static let intermediateSuffix = ".whisper-tmp.wav"

    static func intermediateURL(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent(stem + intermediateSuffix)
    }

    /// `name.md`, or `name-1.md`, `name-2.md`... so an existing transcript is
    /// never silently destroyed.
    static func outputURL(for source: URL, overwrite: Bool) -> URL {
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let plain = dir.appendingPathComponent(stem + ".md")
        if overwrite || !FileManager.default.fileExists(atPath: plain.path) { return plain }
        for n in 1... {
            let candidate = dir.appendingPathComponent("\(stem)-\(n).md")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return plain
    }

    @discardableResult
    static func run(
        _ request: TranscriptionRequest,
        layout: Layout,
        onStage: ((Stage) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil,
        registerHandle: ((RunningProcess) -> Void)? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let source = request.source.resolvingSymlinksInPath()
        let started = Date()

        onStage?(.inspecting)
        let info = try AudioConverter.inspect(source)

        // Only non-conforming audio needs an intermediate file, and it goes
        // beside the original so it is visible in the same Finder window.
        var wav = source
        var createdIntermediate = false
        if !info.isWhisperReady {
            onStage?(.converting)
            wav = intermediateURL(for: source)
            try AudioConverter.convert(source, to: wav)
            createdIntermediate = true
            onLog?("wrote intermediate \(wav.lastPathComponent)")
        } else {
            onLog?("source is already 16 kHz mono PCM — no intermediate file needed")
        }

        // Remove our own intermediate on success; leave it behind on failure so
        // the user can inspect what we fed to whisper. Never touch a file we
        // did not create.
        var succeeded = false
        defer {
            if createdIntermediate && succeeded && !request.keepIntermediateWAV {
                try? fm.removeItem(at: wav)
                onLog?("removed intermediate \(wav.lastPathComponent)")
            } else if createdIntermediate && !succeeded {
                onLog?("kept intermediate \(wav.lastPathComponent) for inspection")
            }
        }

        onStage?(.transcribing(0))
        let output = try WhisperRunner.transcribe(
            wav: wav, layout: layout, options: request.options,
            onProgress: { onStage?(.transcribing($0)) },
            onLog: onLog,
            registerHandle: registerHandle)

        guard !output.segments.isEmpty else { throw TranscriberError.noSpeech(source) }

        onStage?(.writing)
        let result = TranscriptionResult(
            segments: output.segments,
            detectedLanguage: output.detectedLanguage,
            audioDuration: info.duration,
            modelName: layout.modelName,
            usedNeuralEngine: output.usedNeuralEngine,
            processingTime: Date().timeIntervalSince(started))

        let markdown = MarkdownBuilder.document(for: result, source: source)
        let destination = outputURL(for: source, overwrite: request.overwrite)
        try markdown.write(to: destination, atomically: true, encoding: .utf8)

        succeeded = true
        return destination
    }
}
