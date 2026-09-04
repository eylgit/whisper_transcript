import Foundation

/// One timestamped chunk of speech as emitted by whisper-cli.
struct Segment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// One transcribed range of the recording, and what it produced.
struct TranscribedChunk {
    let chunk: Chunk
    let segments: [Segment]
    /// False when a quiet stretch was skipped rather than transcribed. The
    /// distinction matters in the output: "we listened and heard nothing" and
    /// "we did not listen" are different claims, and only one of them is a
    /// guarantee that no speech was missed.
    let wasTranscribed: Bool
}

/// Where a run has got to, in enough detail to be worth showing someone.
struct ChunkProgress: Equatable {
    let index: Int          // zero-based
    let total: Int
    let kind: ChunkKind
    let start: TimeInterval
    let end: TimeInterval
    /// Progress within this chunk, 0...1.
    let fraction: Double

    var overall: Double {
        total > 0 ? (Double(index) + fraction) / Double(total) : 0
    }

    /// e.g. "chunk 3 of 7 · silence · 0:49-1:28"
    var describe: String {
        let kindLabel = kind == .silence ? "silence" : "speech"
        return "chunk \(index + 1) of \(total) · \(kindLabel) · "
             + "\(formatTimestamp(start))-\(formatTimestamp(end))"
    }
}

/// Everything a finished transcription knows about itself.
struct TranscriptionResult {
    let chunks: [TranscribedChunk]
    let detectedLanguage: String?
    let audioDuration: TimeInterval
    let modelName: String
    let usedNeuralEngine: Bool
    let processingTime: TimeInterval
    /// How the recording was divided, for the frontmatter. Nil if not chunked.
    let chunkingSummary: String?

    var segments: [Segment] { chunks.flatMap(\.segments) }
}

func formatTimestamp(_ t: TimeInterval) -> String {
    let total = Int(t.rounded(.down))
    return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
}

/// Human-friendly duration, e.g. "1h 04m 12s" / "4m 12s" / "12s".
func formatDuration(_ t: TimeInterval) -> String {
    let total = Int(t.rounded())
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
    if m > 0 { return String(format: "%dm %02ds", m, s) }
    return "\(s)s"
}
