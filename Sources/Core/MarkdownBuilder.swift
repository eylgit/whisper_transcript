import Foundation

enum MarkdownBuilder {
    /// A paragraph break is considered at a pause this long or longer...
    static let pauseForParagraph: TimeInterval = 1.0
    /// ...but only at a sentence boundary, once the paragraph is at least this long.
    static let softParagraphLength = 750
    /// Absolute ceiling, so a speaker who never pauses still gets readable blocks.
    static let hardParagraphLength = 1500

    // MARK: - Text joining

    private static func isIdeographic(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,   // CJK punctuation
             0x3040...0x30FF,   // kana
             0x3400...0x4DBF,   // CJK ext A
             0x4E00...0x9FFF,   // CJK unified
             0xF900...0xFAFF,   // compatibility ideographs
             0xFF00...0xFFEF,   // fullwidth forms
             0x0E00...0x0E7F:   // Thai
            return true
        default:
            return false
        }
    }

    /// Whisper emits space-separated words for most languages but runs CJK text
    /// together; inserting spaces there would corrupt it.
    private static func needsSpace(after left: Character, before right: Character) -> Bool {
        if left.isWhitespace || right.isWhitespace { return false }
        if isIdeographic(left) || isIdeographic(right) { return false }
        return true
    }

    private static func append(_ text: String, to paragraph: inout String) {
        if let l = paragraph.last, let r = text.first, needsSpace(after: l, before: r) {
            paragraph.append(" ")
        }
        paragraph += text
    }

    private static func endsSentence(_ s: String) -> Bool {
        // Skip trailing closers so `he said."` still counts as a sentence end.
        var t = Substring(s)
        while let last = t.last, "\"'”’)]»".contains(last) { t = t.dropLast() }
        guard let last = t.last else { return false }
        return ".!?。！？…".contains(last)
    }

    // MARK: - Paragraphs

    static func paragraphs(from segments: [Segment]) -> [String] {
        var result: [String] = []
        var current = ""
        var previousEnd: TimeInterval? = nil

        for seg in segments {
            if !current.isEmpty {
                let gap = previousEnd.map { seg.start - $0 } ?? 0
                let atSentenceEnd = endsSentence(current)
                let breakHere =
                    (gap >= pauseForParagraph && atSentenceEnd)
                    || (current.count >= softParagraphLength && atSentenceEnd)
                    || current.count >= hardParagraphLength
                if breakHere {
                    result.append(current)
                    current = ""
                }
            }
            append(seg.text, to: &current)
            previousEnd = seg.end
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Document

    private static func yaml(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func document(for result: TranscriptionResult, source: URL) -> String {
        let title = source.deletingPathExtension().lastPathComponent

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"

        var language = "unknown"
        if let l = result.detectedLanguage {
            let name = Locale.current.localizedString(forLanguageCode: l)
            language = name.map { "\($0) (\(l))" } ?? l
        }

        var out = "---\n"
        out += "source: \(yaml(source.lastPathComponent))\n"
        out += "duration: \(yaml(formatDuration(result.audioDuration)))\n"
        out += "language: \(yaml(language))\n"
        out += "model: \(yaml(result.modelName))\n"
        out += "engine: \(yaml("whisper.cpp — " + (result.usedNeuralEngine ? "Apple Neural Engine + Metal" : "Metal")))\n"
        out += "transcribed: \(yaml(stamp.string(from: Date())))\n"
        out += "processing_time: \(yaml(formatDuration(result.processingTime)))\n"
        if let summary = result.chunkingSummary {
            out += "chunking: \(yaml(summary))\n"
        }
        out += "offline: true\n"
        out += "---\n\n"
        out += "# \(title)\n\n"

        if result.segments.isEmpty {
            out += "_No speech was detected in this recording._\n"
            return out
        }

        for entry in result.chunks {
            switch entry.chunk.kind {
            case .speech:
                let paras = paragraphs(from: entry.segments)
                guard !paras.isEmpty else { continue }
                out += paras.joined(separator: "\n\n") + "\n\n"

            case .silence:
                // A stretch measured as quiet. It is transcribed anyway, because
                // the measurement can be wrong and losing speech silently would
                // be far worse than a redundant marker. It is fenced off and
                // labelled because a quiet stretch is exactly where the model is
                // most likely to invent fluent text that was never spoken.
                let from = formatTimestamp(entry.chunk.start)
                let to = formatTimestamp(entry.chunk.end)
                let length = formatDuration(entry.chunk.duration)

                out += "> ⏸ **Silence — \(from) to \(to)** (\(length))\n"
                guard entry.wasTranscribed else {
                    out += "> Measured as quiet and skipped, so any speech here was not captured.\n"
                    out += "> ⏹ **End of silence — \(to)**\n\n"
                    continue
                }
                out += "> Measured as quiet, transcribed separately as a precaution.\n"
                out += "> Treat anything below as unreliable until the end marker.\n>\n"
                if entry.segments.isEmpty {
                    out += "> _Listened, nothing transcribed._\n>\n"
                } else {
                    for para in paragraphs(from: entry.segments) {
                        out += "> \(para)\n>\n"
                    }
                }
                out += "> ⏹ **End of silence — \(to)**\n\n"
            }
        }

        out += "<details>\n<summary>Timestamped segments</summary>\n\n"
        for entry in result.chunks {
            let marker = entry.chunk.kind == .silence ? " _(in silence)_" : ""
            for seg in entry.segments {
                out += "- `[\(formatTimestamp(seg.start))]`\(marker) \(seg.text)\n"
            }
        }
        out += "\n</details>\n"
        return out
    }
}
