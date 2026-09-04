import Foundation

public struct TranscriptionRequest {
    public let source: URL
    public var options = WhisperOptions()
    /// Keep the intermediate 16 kHz WAV instead of removing it on success.
    public var keepIntermediateWAV = false
    /// Overwrite an existing .md rather than picking the next free name.
    public var overwrite = false
    /// Transcribe the quiet stretches too, rather than only the speech.
    ///
    /// On by default: the loudness measurement can be wrong, and someone
    /// speaking softly would otherwise be dropped without trace. Turning it off
    /// is faster and produces a tidier transcript, at the cost of that
    /// guarantee. Quiet stretches are marked either way, so the reader can
    /// always see where they were.
    public var transcribeSilence = true

    public init(source: URL) { self.source = source }
}

public enum Stage {
    case inspecting
    case converting
    case analysing
    /// Emitted once the work is planned, so a caller can show the whole shape
    /// of the job before it starts rather than only a moving bar.
    case planned(chunks: Int, duration: TimeInterval)
    case transcribing(ChunkProgress)
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

public enum Transcriber {
    /// Marker that makes our intermediate file obvious in Finder next to the original.
    public static let intermediateSuffix = ".whisper-tmp.wav"

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
    public static func run(
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

        // Divide the recording at long pauses. Each chunk is transcribed on its
        // own with no text carried across the boundary, so a decoder that locks
        // into repeating itself cannot spread past the pause it started in.
        var chunks: [Chunk]
        var chunkingSummary: String? = nil
        onStage?(.analysing)
        do {
            let analysis = try SilenceDetector.analyse(wav: wav)
            chunks = ChunkPlanner.plan(duration: info.duration, silences: analysis.regions)
            onLog?("audio: \(analysis.summary)")
            _ = analysis
            if chunks.count > 1 {
                chunkingSummary = "\(chunks.count) chunks; \(analysis.summary)"
            }
        } catch {
            // Never fatal: an unreadable WAV header only costs us the chunking.
            onLog?("silence analysis unavailable (\(error.localizedDescription)); one pass")
            chunks = [Chunk(kind: .speech, start: 0, end: info.duration)]
        }

        onStage?(.planned(chunks: chunks.count, duration: info.duration))

        var transcribed: [TranscribedChunk] = []
        var language: String? = nil
        var usedNeuralEngine = false

        func progress(_ index: Int, _ chunk: Chunk, _ fraction: Double) -> ChunkProgress {
            ChunkProgress(index: index, total: chunks.count, kind: chunk.kind,
                          start: chunk.start, end: chunk.end, fraction: fraction)
        }

        for (index, chunk) in chunks.enumerated() {
            onStage?(.transcribing(progress(index, chunk, 0)))

            // Skipping a quiet stretch is the user's call; it is still recorded
            // and marked, so the transcript never hides that a gap existed.
            if chunk.kind == .silence && !request.transcribeSilence {
                onLog?("chunk \(index + 1)/\(chunks.count): silence skipped by request")
                transcribed.append(TranscribedChunk(chunk: chunk, segments: [],
                                                    wasTranscribed: false))
                continue
            }

            if chunks.count > 1 {
                onLog?(String(format: "chunk %d/%d %@ %.1fs-%.1fs",
                              index + 1, chunks.count,
                              chunk.kind == .silence ? "(silence)" : "(speech)",
                              chunk.start, chunk.end))
            }
            let output = try WhisperRunner.transcribe(
                wav: wav, layout: layout, options: request.options,
                offset: chunk.start,
                duration: chunks.count > 1 ? chunk.duration : nil,
                onProgress: { onStage?(.transcribing(progress(index, chunk, $0))) },
                onLog: onLog,
                registerHandle: registerHandle)

            if language == nil { language = output.detectedLanguage }
            usedNeuralEngine = usedNeuralEngine || output.usedNeuralEngine

            // whisper's --duration bounds where decoding *starts*, not what it
            // reads: each window is a fixed 30s taken from the whole file, so the
            // last window of a chunk sees up to 30s of audio past the requested
            // end. Left alone, a silence chunk swallows the speech that follows
            // it and the same passage appears twice -- once fenced off as
            // unreliable. Keeping only segments whose midpoint lies inside the
            // chunk discards that overrun while leaving genuine segments, which
            // sit well within their chunk because chunks end inside pauses.
            let owned = chunks.count == 1 ? output.segments : output.segments.filter {
                let midpoint = ($0.start + $0.end) / 2
                return midpoint >= chunk.start && midpoint <= chunk.end
            }
            if owned.count != output.segments.count {
                onLog?("chunk \(index + 1): dropped \(output.segments.count - owned.count) segment(s) that overran the chunk")
            }
            transcribed.append(TranscribedChunk(chunk: chunk, segments: owned,
                                                wasTranscribed: true))
        }

        guard transcribed.contains(where: { !$0.segments.isEmpty }) else {
            throw TranscriberError.noSpeech(source)
        }

        onStage?(.writing)
        let result = TranscriptionResult(
            chunks: transcribed,
            detectedLanguage: language,
            audioDuration: info.duration,
            modelName: layout.modelName,
            usedNeuralEngine: usedNeuralEngine,
            processingTime: Date().timeIntervalSince(started),
            chunkingSummary: chunkingSummary)

        let markdown = MarkdownBuilder.document(for: result, source: source)
        let destination = outputURL(for: source, overwrite: request.overwrite)
        try markdown.write(to: destination, atomically: true, encoding: .utf8)

        succeeded = true
        return destination
    }
}
