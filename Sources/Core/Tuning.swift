import Foundation

/// Every tunable number in the transcription pipeline, in one place.
///
/// These are informed by how speech and the Whisper model behave, but they are
/// starting values, not values validated across a corpus of real recordings.
/// Each one says what it does and why it is set where it is, so that changing it
/// is an informed decision rather than a guess.
enum Tuning {

    // MARK: - Deciding what counts as silence

    /// Loudness is judged *relative to each recording*, never against a fixed
    /// level. A quiet phone recording's speech can sit below a studio
    /// recording's room tone, so any absolute threshold is wrong half the time.
    ///
    /// How far above the recording's own noise floor a frame must be to count as
    /// sound. Comfortably clear of room tone, well below speech.
    static let silenceMarginAboveNoiseFloorDB: Double = 8.0

    /// The recording's noise floor is taken as this percentile of frame
    /// loudness, rather than the minimum, so one freak-quiet frame cannot skew it.
    static let noiseFloorPercentile: Double = 5

    /// The recording's speech level, taken high enough to represent real speech
    /// but not the single loudest peak.
    static let speechLevelPercentile: Double = 90

    /// If speech and silence are separated by less than this, the recording is
    /// too noisy or too compressed to tell them apart, and any boundary we chose
    /// would be a guess. Below this the file is transcribed in one pass instead.
    /// Declining to act beats cutting in the wrong place.
    static let minimumDynamicRangeDB: Double = 15.0

    /// Loudness is measured over windows this long. Short enough to locate a
    /// pause precisely, long enough to be a stable measurement.
    static let analysisFrameSeconds: Double = 0.025

    /// Once inside a silence, a frame must exceed the threshold by this much to
    /// end it. Without this margin, audio hovering at the threshold flickers in
    /// and out and produces dozens of bogus micro-pauses.
    static let silenceExitHysteresisDB: Double = 3.0

    // MARK: - Deciding where to cut

    /// How long a quiet stretch must be before it is treated as a chunk boundary.
    ///
    /// Pause lengths carry meaning: ~0.2s is a breath, ~0.5s ends a sentence,
    /// 1-2s ends a thought. At 3s the speaker has genuinely stopped. Boundaries
    /// need to be confident rather than frequent, and we only need a handful in
    /// an hour, so this is deliberately conservative.
    ///
    /// It is also the main cost lever: every chunk carries a fixed ~3.2s
    /// overhead (measured), so lowering this makes transcription slower.
    static let minimumSilenceSeconds: TimeInterval = 3.0

    /// How much silence each speech chunk keeps on the side facing a pause.
    ///
    /// Half the minimum silence, so a qualifying pause always has enough room to
    /// give both neighbours their buffer without the two overlapping past each
    /// other. Speech chunks therefore never end on a hard cut at the last
    /// syllable, and the model sees the leading and trailing quiet it expects.
    static var silenceBufferSeconds: TimeInterval { minimumSilenceSeconds / 2 }

    /// Chunks shorter than this are dropped rather than transcribed. Not a
    /// minimum chunk length: purely a guard against degenerate zero-width chunks
    /// thrown up by silence at the very start or end of a file, which would cost
    /// a full ~3.2s launch to transcribe nothing.
    static let negligibleChunkSeconds: TimeInterval = 0.25

    /// Below this total duration, chunking is skipped entirely. A short file has
    /// little room for a loop to do damage, and a single pass stays simplest.
    static let minimumDurationToChunkSeconds: TimeInterval = 120
}
