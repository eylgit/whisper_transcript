import XCTest
@testable import TranscribeCore

final class SilenceDetectorTests: XCTestCase {

    private let rate = 16_000
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("silence-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Builds a 16-bit mono WAV from (seconds, amplitude) runs. The signal
    /// alternates ±amplitude every sample, so each run's RMS is exactly its
    /// amplitude and the resulting dBFS is predictable.
    private func makeWAV(_ runs: [(seconds: Double, amplitude: Int16)],
                         channels: Int = 1, bitsPerSample: Int = 16) throws -> URL {
        var samples = [Int16]()
        for run in runs {
            let n = Int(run.seconds * Double(rate))
            for i in 0..<n { samples.append(i % 2 == 0 ? run.amplitude : -run.amplitude) }
        }
        var pcm = Data(capacity: samples.count * 2)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { pcm.append(contentsOf: $0) } }

        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }

        var out = Data("RIFF".utf8)
        out += le32(36 + pcm.count)
        out += Data("WAVEfmt ".utf8)
        out += le32(16)                                   // PCM fmt chunk size
        out += le16(1)                                    // format = PCM
        out += le16(channels)
        out += le32(rate)
        out += le32(rate * channels * bitsPerSample / 8)  // byte rate
        out += le16(channels * bitsPerSample / 8)         // block align
        out += le16(bitsPerSample)
        out += Data("data".utf8)
        out += le32(pcm.count)
        out += pcm

        let url = scratch.appendingPathComponent("\(UUID().uuidString).wav")
        try out.write(to: url)
        return url
    }

    // Roughly -14 dBFS and -66 dBFS: a comfortable 52 dB apart.
    private let speech: Int16 = 6553
    private let quiet: Int16 = 16

    func testFindsAPauseBetweenTwoStretchesOfSpeech() throws {
        let url = try makeWAV([(5, speech), (4, quiet), (5, speech)])
        let analysis = try SilenceDetector.analyse(wav: url)
        XCTAssertEqual(analysis.regions.count, 1)
        let region = try XCTUnwrap(analysis.regions.first)
        XCTAssertEqual(region.start, 5, accuracy: 0.1)
        XCTAssertEqual(region.end, 9, accuracy: 0.1)
        XCTAssertGreaterThan(analysis.dynamicRangeDB, Tuning.minimumDynamicRangeDB)
    }

    func testAPauseShorterThanTheMinimumIsIgnored() throws {
        let url = try makeWAV([(5, speech), (2, quiet), (5, speech)])
        XCTAssertEqual(try SilenceDetector.analyse(wav: url).regions.count, 0,
                       "2s is a breath, not a boundary")
    }

    func testFindsSeveralPauses() throws {
        let url = try makeWAV([
            (5, speech), (4, quiet), (5, speech), (4, quiet), (5, speech),
        ])
        XCTAssertEqual(try SilenceDetector.analyse(wav: url).regions.count, 2)
    }

    /// The refusal to guess. When speech and room tone are too close together,
    /// any boundary chosen would be arbitrary, so none is reported and the
    /// caller transcribes in a single pass.
    func testTooLittleDynamicRangeReportsNoPausesRatherThanGuessing() throws {
        let url = try makeWAV([(5, 100), (4, 50), (5, 100)])   // ~6 dB apart
        let analysis = try SilenceDetector.analyse(wav: url)
        XCTAssertLessThan(analysis.dynamicRangeDB, Tuning.minimumDynamicRangeDB)
        XCTAssertTrue(analysis.regions.isEmpty, "a noisy recording must not be cut blindly")
        XCTAssertTrue(analysis.summary.contains("no qualifying pauses"))
    }

    func testSilenceIsJudgedRelativeToTheRecordingNotAnAbsoluteLevel() throws {
        // A loud recording and a quiet one with the same *shape* must both yield
        // the same pause. A fixed threshold would find it in only one of them.
        let loud = try SilenceDetector.analyse(
            wav: try makeWAV([(5, 20000), (4, 60), (5, 20000)]))
        let faint = try SilenceDetector.analyse(
            wav: try makeWAV([(5, 600), (4, 2), (5, 600)]))
        XCTAssertEqual(loud.regions.count, 1)
        XCTAssertEqual(faint.regions.count, 1)
        XCTAssertEqual(loud.regions[0].start, faint.regions[0].start, accuracy: 0.1)
    }

    func testAllSpeechYieldsNoPauses() throws {
        XCTAssertTrue(try SilenceDetector.analyse(wav: try makeWAV([(10, speech)])).regions.isEmpty)
    }

    func testStereoIsRejectedRatherThanMisread() throws {
        let url = try makeWAV([(5, speech)], channels: 2)
        XCTAssertThrowsError(try SilenceDetector.analyse(wav: url))
    }

    func testNonWAVDataIsRejected() throws {
        let url = scratch.appendingPathComponent("not-audio.wav")
        try Data("this is not a RIFF file at all, not even close to one".utf8).write(to: url)
        XCTAssertThrowsError(try SilenceDetector.analyse(wav: url))
    }

    func testSummaryDescribesWhatWasDecided() throws {
        let s = try SilenceDetector.analyse(wav: try makeWAV([(5, speech), (4, quiet), (5, speech)])).summary
        XCTAssertTrue(s.contains("pause(s)"))
        XCTAssertTrue(s.contains("noise floor"))
    }
}
