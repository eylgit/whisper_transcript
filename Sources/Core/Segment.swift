import Foundation

/// One timestamped chunk of speech as emitted by whisper-cli.
struct Segment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// Everything a finished transcription knows about itself.
struct TranscriptionResult {
    let segments: [Segment]
    let detectedLanguage: String?
    let audioDuration: TimeInterval
    let modelName: String
    let usedNeuralEngine: Bool
    let processingTime: TimeInterval
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
