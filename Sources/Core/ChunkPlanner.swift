import Foundation

public enum ChunkKind: Equatable {
    case speech
    /// A stretch the loudness analysis judged quiet. Transcribed anyway, because
    /// the analysis can be wrong and quietly dropping speech is the worst thing
    /// this tool could do. Marked in the output so the reader knows to be wary.
    case silence
}

struct Chunk {
    let kind: ChunkKind
    let start: TimeInterval
    let end: TimeInterval
    var duration: TimeInterval { end - start }
}

/// Turns detected pauses into the list of ranges to transcribe.
///
/// Around each qualifying pause the audio is covered three times over:
///
///     ...speech A...  [========= pause =========]  ...speech B...
///                     ^                         ^
///                  pauseStart                pauseEnd
///
///     speech   [ ...A... --- pauseStart+buffer ]
///     silence           [ pauseStart --------- pauseEnd ]
///     speech                        [ pauseEnd-buffer --- ...B... ]
///
/// The two overlaps are inside the pause, so they should contribute no text.
/// They exist so that no audio can fall in a crack between chunks: every instant
/// of the recording belongs to at least one chunk. Coverage is deliberately
/// redundant rather than exact, because a gap would mean silently lost words
/// while an overlap merely means a duplicated moment of quiet.
///
/// Each chunk is transcribed independently with no text carried across
/// boundaries, so a decoder that locks into repeating itself cannot spread the
/// damage past the pause it started in.
enum ChunkPlanner {

    static func plan(duration: TimeInterval, silences: [SilenceRegion]) -> [Chunk] {
        guard duration >= Tuning.minimumDurationToChunkSeconds, !silences.isEmpty else {
            return [Chunk(kind: .speech, start: 0, end: duration)]
        }

        let buffer = Tuning.silenceBufferSeconds
        var chunks: [Chunk] = []
        var cursor: TimeInterval = 0

        func appendIfWorthwhile(_ kind: ChunkKind, _ start: TimeInterval, _ end: TimeInterval) {
            let s = max(0, start), e = min(duration, end)
            guard e - s > Tuning.negligibleChunkSeconds else { return }
            chunks.append(Chunk(kind: kind, start: s, end: e))
        }

        for silence in silences.sorted(by: { $0.start < $1.start }) {
            // Ignore a pause already covered by the previous one's trailing buffer.
            guard silence.end > cursor else { continue }

            appendIfWorthwhile(.speech, cursor, silence.start + buffer)
            appendIfWorthwhile(.silence, silence.start, silence.end)
            cursor = max(cursor, silence.end - buffer)
        }
        appendIfWorthwhile(.speech, cursor, duration)

        return chunks.isEmpty ? [Chunk(kind: .speech, start: 0, end: duration)] : chunks
    }
}
