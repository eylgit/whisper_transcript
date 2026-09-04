import XCTest
@testable import TranscribeCore

/// Where files land, and the promise that an existing transcript is never
/// destroyed without being asked.
final class OutputNamingTests: XCTestCase {

    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naming-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func touch(_ name: String) throws {
        try Data().write(to: dir.appendingPathComponent(name))
    }

    func testTranscriptLandsBesideTheAudio() {
        let source = dir.appendingPathComponent("meeting.m4a")
        let out = Transcriber.outputURL(for: source, overwrite: false)
        XCTAssertEqual(out.lastPathComponent, "meeting.md")
        XCTAssertEqual(out.deletingLastPathComponent().path, dir.path,
                       "never /tmp, never a hidden cache")
    }

    func testAnExistingTranscriptIsNumberedRatherThanOverwritten() throws {
        try touch("meeting.md")
        let out = Transcriber.outputURL(for: dir.appendingPathComponent("meeting.m4a"),
                                        overwrite: false)
        XCTAssertEqual(out.lastPathComponent, "meeting-1.md")
    }

    func testNumberingSkipsPastEveryExistingTranscript() throws {
        try touch("meeting.md"); try touch("meeting-1.md"); try touch("meeting-2.md")
        let out = Transcriber.outputURL(for: dir.appendingPathComponent("meeting.m4a"),
                                        overwrite: false)
        XCTAssertEqual(out.lastPathComponent, "meeting-3.md")
    }

    func testForceOverwritesTheOriginalName() throws {
        try touch("meeting.md")
        let out = Transcriber.outputURL(for: dir.appendingPathComponent("meeting.m4a"),
                                        overwrite: true)
        XCTAssertEqual(out.lastPathComponent, "meeting.md")
    }

    func testIntermediateWAVIsObviousAndSitsBesideTheSource() {
        let wav = Transcriber.intermediateURL(for: dir.appendingPathComponent("meeting.m4a"))
        XCTAssertEqual(wav.lastPathComponent, "meeting" + Transcriber.intermediateSuffix)
        XCTAssertEqual(wav.deletingLastPathComponent().path, dir.path)
        XCTAssertTrue(wav.lastPathComponent.contains("whisper-tmp"),
                      "it should be recognisable in Finder as ours")
    }

    func testDotsInTheNameAreNotMistakenForTheExtension() {
        let out = Transcriber.outputURL(for: dir.appendingPathComponent("2026.01.03 standup.m4a"),
                                        overwrite: false)
        XCTAssertEqual(out.lastPathComponent, "2026.01.03 standup.md")
    }

    func testDurationsReadAsPeopleWriteThem() {
        XCTAssertEqual(formatDuration(12), "12s")
        XCTAssertEqual(formatDuration(252), "4m 12s")
        XCTAssertEqual(formatDuration(3852), "1h 04m 12s")
        XCTAssertEqual(formatTimestamp(3852), "01:04:12")
    }

    func testProgressDescribesTheWholeJobNotJustAPercentage() {
        let p = ChunkProgress(index: 2, total: 7, kind: .silence,
                              start: 49, end: 88, fraction: 0.5)
        XCTAssertEqual(p.describe, "chunk 3 of 7 · silence · 00:00:49-00:01:28")
        XCTAssertEqual(p.overall, (2.0 + 0.5) / 7.0, accuracy: 1e-9)
    }
}
