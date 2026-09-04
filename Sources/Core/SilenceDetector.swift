import Foundation

struct SilenceRegion {
    let start: TimeInterval
    let end: TimeInterval
    var duration: TimeInterval { end - start }
}

/// What the loudness analysis concluded about a recording.
struct SilenceAnalysis {
    let regions: [SilenceRegion]
    let noiseFloorDB: Double
    let speechLevelDB: Double
    let thresholdDB: Double

    var dynamicRangeDB: Double { speechLevelDB - noiseFloorDB }

    /// A one-line account of what was decided, for the run log. The tool should
    /// be able to explain its own boundaries rather than just assert them.
    var summary: String {
        let range = String(format: "%.0f dB", dynamicRangeDB)
        let floor = String(format: "%.0f dB", noiseFloorDB)
        guard !regions.isEmpty else {
            return "no qualifying pauses (noise floor \(floor), range \(range))"
        }
        let shortest = regions.map(\.duration).min() ?? 0
        let longest = regions.map(\.duration).max() ?? 0
        return String(format: "%d pause(s) of %.1f-%.1fs (noise floor %@, range %@)",
                      regions.count, shortest, longest, floor, range)
    }
}

/// Finds quiet stretches by measuring loudness relative to the recording itself.
///
/// Deliberately simple: we do not need to know precisely where speech is, only
/// where the recording is confidently quiet for long enough to be a safe place
/// to cut. That job does not warrant a machine-learning model, and doing it with
/// plain arithmetic keeps the whole pipeline readable.
enum SilenceDetector {

    enum DetectorError: LocalizedError {
        case unsupportedWAV(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedWAV(let why): return "Could not read WAV samples: \(why)"
            }
        }
    }

    // MARK: - Minimal WAV reading

    /// Locates the PCM payload of a RIFF/WAVE file by walking its chunks.
    /// Only the 16-bit mono form we feed to whisper is accepted; anything else
    /// returns nil and the caller falls back to a single pass.
    private static func pcmPayload(_ data: Data) throws -> (samples: Data, sampleRate: Int) {
        func u32(_ o: Int) -> Int {
            guard o + 4 <= data.count else { return 0 }
            return Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8
                 | Int(data[data.startIndex + o + 2]) << 16 | Int(data[data.startIndex + o + 3]) << 24
        }
        func u16(_ o: Int) -> Int {
            guard o + 2 <= data.count else { return 0 }
            return Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8
        }
        func tag(_ o: Int) -> String {
            guard o + 4 <= data.count else { return "" }
            return String(bytes: data[(data.startIndex + o)..<(data.startIndex + o + 4)],
                          encoding: .ascii) ?? ""
        }

        guard data.count > 44, tag(0) == "RIFF", tag(8) == "WAVE" else {
            throw DetectorError.unsupportedWAV("not a RIFF/WAVE file")
        }

        var channels = 0, bits = 0, rate = 0
        var offset = 12
        while offset + 8 <= data.count {
            let id = tag(offset)
            let size = u32(offset + 4)
            let body = offset + 8
            if id == "fmt " {
                channels = u16(body + 2)
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                let end = min(body + size, data.count)
                guard channels == 1, bits == 16, rate > 0 else {
                    throw DetectorError.unsupportedWAV(
                        "expected 16-bit mono PCM, found \(channels)ch/\(bits)-bit")
                }
                return (data.subdata(in: (data.startIndex + body)..<(data.startIndex + end)), rate)
            }
            offset = body + size + (size % 2)   // RIFF chunks are word-aligned
        }
        throw DetectorError.unsupportedWAV("no data chunk found")
    }

    // MARK: - Analysis

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int((p / 100 * Double(sorted.count - 1)).rounded())
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }

    static func analyse(wav url: URL) throws -> SilenceAnalysis {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let (payload, sampleRate) = try pcmPayload(data)

        let frameLength = max(1, Int(Tuning.analysisFrameSeconds * Double(sampleRate)))
        let sampleCount = payload.count / 2
        guard sampleCount > frameLength else {
            return SilenceAnalysis(regions: [], noiseFloorDB: 0, speechLevelDB: 0, thresholdDB: 0)
        }

        // Loudness of each frame in dBFS. Decibels, not raw amplitude: hearing and
        // acoustic dynamic range are logarithmic, and a linear threshold behaves
        // badly at exactly the low levels we care about here.
        var frameDB: [Double] = []
        frameDB.reserveCapacity(sampleCount / frameLength)
        payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            var i = 0
            while i + frameLength <= samples.count {
                var sumSquares = 0.0
                for j in i..<(i + frameLength) {
                    let v = Double(Int16(littleEndian: samples[j]))
                    sumSquares += v * v
                }
                let rms = (sumSquares / Double(frameLength)).squareRoot()
                frameDB.append(rms > 0 ? 20 * log10(rms / 32768.0) : -120.0)
                i += frameLength
            }
        }
        guard !frameDB.isEmpty else {
            return SilenceAnalysis(regions: [], noiseFloorDB: 0, speechLevelDB: 0, thresholdDB: 0)
        }

        let sorted = frameDB.sorted()
        let noiseFloor = percentile(sorted, Tuning.noiseFloorPercentile)
        let speechLevel = percentile(sorted, Tuning.speechLevelPercentile)
        let threshold = noiseFloor + Tuning.silenceMarginAboveNoiseFloorDB

        // Too little separation between quiet and loud means we cannot tell them
        // apart, so we report no regions and the caller transcribes in one pass.
        guard speechLevel - noiseFloor >= Tuning.minimumDynamicRangeDB else {
            return SilenceAnalysis(regions: [], noiseFloorDB: noiseFloor,
                                   speechLevelDB: speechLevel, thresholdDB: threshold)
        }

        // Walk the frames with hysteresis: enter silence below the threshold,
        // leave it only once clearly above, so borderline audio cannot flicker.
        let exitThreshold = threshold + Tuning.silenceExitHysteresisDB
        let frameSeconds = Double(frameLength) / Double(sampleRate)
        var regions: [SilenceRegion] = []
        var runStart: Int? = nil

        func closeRun(at index: Int) {
            guard let start = runStart else { return }
            let region = SilenceRegion(start: Double(start) * frameSeconds,
                                       end: Double(index) * frameSeconds)
            if region.duration >= Tuning.minimumSilenceSeconds { regions.append(region) }
            runStart = nil
        }

        for (i, db) in frameDB.enumerated() {
            if runStart == nil {
                if db < threshold { runStart = i }
            } else if db > exitThreshold {
                closeRun(at: i)
            }
        }
        closeRun(at: frameDB.count)

        return SilenceAnalysis(regions: regions, noiseFloorDB: noiseFloor,
                               speechLevelDB: speechLevel, thresholdDB: threshold)
    }
}
